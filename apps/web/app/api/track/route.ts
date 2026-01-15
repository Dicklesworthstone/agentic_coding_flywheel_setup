import { NextRequest, NextResponse } from 'next/server';

const GA_MEASUREMENT_ID_RAW = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID;
const GA_API_SECRET_RAW = process.env.GA_API_SECRET;

function sanitizeGaMeasurementId(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;

  let cleaned = value.trim();
  if (!cleaned) return undefined;

  // Handle accidental quoting in env var values (common copy/paste mistake).
  if (
    (cleaned.startsWith('"') && cleaned.endsWith('"')) ||
    (cleaned.startsWith("'") && cleaned.endsWith("'"))
  ) {
    cleaned = cleaned.slice(1, -1).trim();
  }

  // Remove common trailing garbage (escaped newlines, whitespace sequences)
  // that can appear from misconfigured env vars or Vercel CLI pulls.
  cleaned = cleaned.replace(/\\n$/, '').replace(/\s+$/, '');

  // Extract valid GA4 measurement ID (G-XXXXXXXXXX).
  // Use extraction rather than strict matching to handle edge cases.
  const match = cleaned.match(/^(G-[A-Z0-9]+)/i);
  if (match) return match[1];

  return undefined;
}

function sanitizeGaApiSecret(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  // Remove trailing escaped newlines from Vercel CLI pulls
  const cleaned = value.trim().replace(/\\n$/, '');
  if (!cleaned || cleaned.length > 200) return undefined;
  return cleaned;
}

const GA_MEASUREMENT_ID = sanitizeGaMeasurementId(GA_MEASUREMENT_ID_RAW);
const GA_API_SECRET = sanitizeGaApiSecret(GA_API_SECRET_RAW);

// Rate limiting configuration
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute
const RATE_LIMIT_MAX_REQUESTS = 60; // 60 requests per minute per IP
const MAX_EVENTS_PER_REQUEST = 10;
const MAX_CLIENT_ID_LENGTH = 100;
const MAX_EVENT_NAME_LENGTH = 40;
const MAX_REQUEST_BODY_BYTES = 32_000; // hard cap to reduce abuse/memory pressure
const MAX_PARAM_KEYS_PER_EVENT = 25;
const MAX_PARAM_KEY_LENGTH = 40;
const MAX_PARAM_STRING_LENGTH = 300;
const MAX_USER_ID_LENGTH = 64;
const MAX_USER_PROPERTIES = 10;
const MAX_USER_PROPERTY_KEY_LENGTH = 24;
const MAX_USER_PROPERTY_STRING_LENGTH = 120;
const GA_FETCH_TIMEOUT_MS = 3000;

class PayloadTooLargeError extends Error {
  override name = 'PayloadTooLargeError';
}

async function readJsonBodyWithLimit(request: NextRequest): Promise<unknown> {
  const reader = request.body?.getReader();
  if (!reader) {
    // Fall back to the built-in helper when the body stream isn't available.
    return request.json();
  }

  const decoder = new TextDecoder();
  let bytesRead = 0;
  let text = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!value) continue;

    bytesRead += value.byteLength;
    if (bytesRead > MAX_REQUEST_BODY_BYTES) {
      try {
        await reader.cancel();
      } catch {
        // ignore
      }
      throw new PayloadTooLargeError();
    }

    text += decoder.decode(value, { stream: true });
  }

  text += decoder.decode();
  try {
    return JSON.parse(text) as unknown;
  } catch (error) {
    // Normalize error handling at the call site (e.g., SyntaxError -> 400).
    throw error;
  }
}

// Simple in-memory rate limiter (resets on server restart)
const rateLimitMap = new Map<string, { count: number; resetTime: number }>();

// Cleanup interval tracking - cleanup runs every ~100 requests to bound memory
let requestsSinceCleanup = 0;
const CLEANUP_INTERVAL = 100;
const MAX_MAP_SIZE = 10000; // Hard limit to prevent runaway growth

function cleanupExpiredEntries(): void {
  const now = Date.now();
  for (const [ip, record] of rateLimitMap.entries()) {
    if (now > record.resetTime) {
      rateLimitMap.delete(ip);
    }
  }
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function normalizeIP(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed) return 'unknown';
  if (trimmed.length > 80) return 'unknown';

  // [IPv6]:port
  if (trimmed.startsWith('[')) {
    const endIdx = trimmed.indexOf(']');
    if (endIdx > 1) {
      return normalizeIP(trimmed.slice(1, endIdx));
    }
    return 'unknown';
  }

  // IPv4:port
  if (trimmed.includes('.') && trimmed.includes(':')) {
    const beforePort = trimmed.split(':')[0]?.trim();
    if (beforePort) return normalizeIP(beforePort);
  }

  // IPv4
  if (trimmed.includes('.')) {
    const parts = trimmed.split('.');
    if (parts.length !== 4) return 'unknown';
    for (const part of parts) {
      if (!/^\d{1,3}$/.test(part)) return 'unknown';
      const n = Number(part);
      if (!Number.isInteger(n) || n < 0 || n > 255) return 'unknown';
    }
    return trimmed;
  }

  // IPv6 (basic validation; exact canonicalization is unnecessary for rate limiting)
  if (trimmed.includes(':') && /^[0-9a-fA-F:]+$/.test(trimmed) && trimmed.length <= 45) {
    return trimmed.toLowerCase();
  }

  return 'unknown';
}

function getClientIP(request: NextRequest): string {
  const requestIP = (request as unknown as { ip?: string }).ip;
  const forwardedFor =
    request.headers.get('x-vercel-forwarded-for') ||
    request.headers.get('x-forwarded-for');

  return (
    normalizeIP(
      requestIP ||
        forwardedFor?.split(',')[0]?.trim() ||
        request.headers.get('cf-connecting-ip') ||
        request.headers.get('x-real-ip') ||
        ''
    ) || 'unknown'
  );
}

function isRateLimited(ip: string): boolean {
  const now = Date.now();

  // Periodic cleanup to prevent unbounded memory growth
  requestsSinceCleanup++;
  if (requestsSinceCleanup >= CLEANUP_INTERVAL || rateLimitMap.size > MAX_MAP_SIZE) {
    cleanupExpiredEntries();
    requestsSinceCleanup = 0;
  }

  const record = rateLimitMap.get(ip);

  if (!record || now > record.resetTime) {
    // Hard cap: don't allow unbounded growth if IP signal becomes untrusted/unique.
    if (!record && rateLimitMap.size >= MAX_MAP_SIZE) {
      return true;
    }
    rateLimitMap.set(ip, { count: 1, resetTime: now + RATE_LIMIT_WINDOW_MS });
    return false;
  }

  if (record.count >= RATE_LIMIT_MAX_REQUESTS) {
    return true;
  }

  record.count++;
  return false;
}

// Validate event name: alphanumeric and underscores only, starts with letter
function isValidEventName(name: string): boolean {
  if (!name || name.length > MAX_EVENT_NAME_LENGTH) return false;
  return /^[a-zA-Z][a-zA-Z0-9_]*$/.test(name);
}

// Validate client_id: reasonable format and length
function isValidClientId(clientId: string): boolean {
  if (!clientId || clientId.length > MAX_CLIENT_ID_LENGTH) return false;
  // Allow alphanumeric, dots, dashes, underscores
  return /^[a-zA-Z0-9._-]+$/.test(clientId);
}

function isValidUserId(userId: string): boolean {
  if (!userId || userId.length > MAX_USER_ID_LENGTH) return false;
  return /^[a-zA-Z0-9._-]+$/.test(userId);
}

function isValidParamKey(key: string): boolean {
  if (!key || key.length > MAX_PARAM_KEY_LENGTH) return false;
  return /^[a-zA-Z][a-zA-Z0-9_]*$/.test(key);
}

function sanitizeEventParams(params: unknown): Record<string, string | number | boolean> {
  if (!isPlainObject(params)) return {};

  const sanitized: Record<string, string | number | boolean> = {};
  let count = 0;

  for (const [key, value] of Object.entries(params)) {
    if (count >= MAX_PARAM_KEYS_PER_EVENT) break;
    if (!isValidParamKey(key)) continue;

    if (typeof value === 'string') {
      sanitized[key] = value.slice(0, MAX_PARAM_STRING_LENGTH);
      count++;
      continue;
    }
    if (typeof value === 'number') {
      if (!Number.isFinite(value)) continue;
      sanitized[key] = value;
      count++;
      continue;
    }
    if (typeof value === 'boolean') {
      sanitized[key] = value;
      count++;
    }
  }

  return sanitized;
}

function sanitizeUserProperties(
  userProperties: unknown
): Record<string, { value: string | number }> | undefined {
  if (!isPlainObject(userProperties)) return undefined;

  const sanitized: Record<string, { value: string | number }> = {};
  let count = 0;

  for (const [key, value] of Object.entries(userProperties)) {
    if (count >= MAX_USER_PROPERTIES) break;
    if (!key || key.length > MAX_USER_PROPERTY_KEY_LENGTH) continue;
    if (!/^[a-zA-Z][a-zA-Z0-9_]*$/.test(key)) continue;
    if (!isPlainObject(value) || !('value' in value)) continue;

    const rawValue = (value as Record<string, unknown>).value;
    if (typeof rawValue === 'string') {
      sanitized[key] = { value: rawValue.slice(0, MAX_USER_PROPERTY_STRING_LENGTH) };
      count++;
      continue;
    }
    if (typeof rawValue === 'number') {
      if (!Number.isFinite(rawValue)) continue;
      sanitized[key] = { value: rawValue };
      count++;
    }
  }

  return count > 0 ? sanitized : undefined;
}

interface EventPayload {
  name: string;
  params?: Record<string, string | number | boolean>;
}

/**
 * Server-side GA4 Measurement Protocol endpoint
 * Bypasses ad blockers and provides reliable tracking
 *
 * POST /api/track
 * Body: { client_id, events: [{ name, params }], user_id?, user_properties? }
 */
export async function POST(request: NextRequest) {
  const contentType = request.headers.get('content-type') || '';
  if (!contentType.toLowerCase().includes('application/json')) {
    return NextResponse.json({ error: 'Unsupported content type' }, { status: 415 });
  }

  const contentLength = request.headers.get('content-length');
  if (contentLength) {
    const bytes = Number(contentLength);
    if (Number.isFinite(bytes) && bytes > MAX_REQUEST_BODY_BYTES) {
      return NextResponse.json({ error: 'Payload too large' }, { status: 413 });
    }
  }

  // Rate limiting
  const clientIP = getClientIP(request);
  if (isRateLimited(clientIP)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded' },
      {
        status: 429,
        headers: { 'Retry-After': Math.ceil(RATE_LIMIT_WINDOW_MS / 1000).toString() },
      }
    );
  }

  if (!GA_MEASUREMENT_ID || !GA_API_SECRET) {
    return NextResponse.json(
      { error: 'Analytics not configured' },
      { status: 503 }
    );
  }

  try {
    const rawBody: unknown = await readJsonBodyWithLimit(request);
    if (!isPlainObject(rawBody)) {
      return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
    }

    const clientId = rawBody.client_id;
    const events = rawBody.events;
    const userId = rawBody.user_id;
    const userProperties = rawBody.user_properties;

    if (typeof clientId !== 'string' || !Array.isArray(events)) {
      return NextResponse.json({ error: 'Missing client_id or events' }, { status: 400 });
    }

    // Validate required fields
    if (!clientId || events.length === 0) {
      return NextResponse.json(
        { error: 'Missing client_id or events' },
        { status: 400 }
      );
    }

    // Validate client_id format
    if (!isValidClientId(clientId)) {
      return NextResponse.json(
        { error: 'Invalid client_id format' },
        { status: 400 }
      );
    }

    // Limit number of events per request
    if (events.length > MAX_EVENTS_PER_REQUEST) {
      return NextResponse.json(
        { error: `Maximum ${MAX_EVENTS_PER_REQUEST} events per request` },
        { status: 400 }
      );
    }

    if (userId !== undefined) {
      if (typeof userId !== 'string' || !isValidUserId(userId)) {
        return NextResponse.json({ error: 'Invalid user_id format' }, { status: 400 });
      }
    }

    const sanitizedUserProperties = sanitizeUserProperties(userProperties);

    const sanitizedEvents: EventPayload[] = [];

    // Validate all event names
    for (const event of events) {
      if (!isPlainObject(event) || typeof event.name !== 'string') {
        return NextResponse.json({ error: 'Invalid event payload' }, { status: 400 });
      }
      if (!isValidEventName(event.name)) {
        return NextResponse.json(
          { error: `Invalid event name: ${event.name?.slice(0, 20)}` },
          { status: 400 }
        );
      }
      sanitizedEvents.push({ name: event.name, params: sanitizeEventParams(event.params) });
    }

    const rawSessionId = clientId.split('.')[1] || '';
    const parsedSessionId = Number(rawSessionId);
    const sessionId =
      Number.isSafeInteger(parsedSessionId) && parsedSessionId > 0
        ? parsedSessionId
        : Math.floor(Date.now() / 1000);

    if (sanitizedEvents.length === 0) {
      return NextResponse.json({ error: 'No valid events' }, { status: 400 });
    }

    // Build the Measurement Protocol payload
    const payload = {
      client_id: clientId,
      events: sanitizedEvents.map(event => ({
        name: event.name,
        params: {
          ...event.params,
          engagement_time_msec: 100,
          session_id: sessionId,
        },
      })),
      ...(userId && { user_id: userId }),
      ...(sanitizedUserProperties && { user_properties: sanitizedUserProperties }),
    };

    // Send to GA4 Measurement Protocol
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), GA_FETCH_TIMEOUT_MS);

    let response: Response;
    try {
      const endpoint = new URL('https://www.google-analytics.com/mp/collect');
      endpoint.searchParams.set('measurement_id', GA_MEASUREMENT_ID);
      endpoint.searchParams.set('api_secret', GA_API_SECRET);

      response = await fetch(
        endpoint.toString(),
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
          signal: controller.signal,
        }
      );
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      console.error('GA4 MP error:', response.status, await response.text());
      return NextResponse.json(
        { error: 'Failed to send to analytics' },
        { status: 502 }
      );
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Track API error:', error);
    if (error instanceof PayloadTooLargeError) {
      return NextResponse.json({ error: 'Payload too large' }, { status: 413 });
    }
    if (error instanceof SyntaxError) {
      return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 });
    }

    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}

// Health check endpoint
export async function GET() {
  return NextResponse.json({
    configured: !!(GA_MEASUREMENT_ID && GA_API_SECRET),
    measurementId: GA_MEASUREMENT_ID ? `${GA_MEASUREMENT_ID.slice(0, 4)}...` : null,
  });
}
