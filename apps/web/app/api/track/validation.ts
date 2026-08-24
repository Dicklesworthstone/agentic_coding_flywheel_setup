import {
  analyticsPayloadIsPrivacySafe,
  SERVER_ANALYTICS_EVENT_NAMES,
  SERVER_CONVERSION_VALUES,
  type ServerAnalyticsEventName,
  type ServerConversionType,
} from '@/lib/analytics';
import { getLessonById, TOTAL_LESSONS } from '@/lib/lessons';

export const MAX_CLIENT_ID_LENGTH = 100;
export const MAX_EVENT_NAME_LENGTH = 40;
export const MAX_PARAM_KEYS_PER_EVENT = 25;
export const MAX_PARAM_KEY_LENGTH = 40;
export const MAX_PARAM_STRING_LENGTH = 300;
export const MAX_LESSON_FUNNEL_MINUTES = 525_600;

export const ALLOWED_SERVER_EVENT_NAMES = new Set<ServerAnalyticsEventName>(
  SERVER_ANALYTICS_EVENT_NAMES
);

export const ALLOWED_LESSON_COMPLETION_PERCENTAGES = new Set(
  Array.from(
    { length: TOTAL_LESSONS },
    (_, index) => Math.round(((index + 1) / TOTAL_LESSONS) * 100)
  )
);

function isPlainObject(value: unknown): value is Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function hasExactlyKeys(record: Record<string, unknown>, expectedKeys: readonly string[]): boolean {
  const actualKeys = Object.keys(record);
  if (actualKeys.length !== expectedKeys.length) return false;
  return expectedKeys.every((key) => Object.prototype.hasOwnProperty.call(record, key));
}

export function isValidServerEventName(name: string): name is ServerAnalyticsEventName {
  if (!name || name.length > MAX_EVENT_NAME_LENGTH) return false;
  return /^[a-z][a-z0-9_]*$/.test(name)
    && ALLOWED_SERVER_EVENT_NAMES.has(name as ServerAnalyticsEventName);
}

export function isValidClientId(clientId: string): boolean {
  if (!clientId || clientId.length > MAX_CLIENT_ID_LENGTH) return false;
  return /^\d{1,16}\.\d{1,16}$/.test(clientId);
}

export function isValidParamKey(key: string): boolean {
  if (!key || key.length > MAX_PARAM_KEY_LENGTH) return false;
  return /^[a-zA-Z][a-zA-Z0-9_]*$/.test(key);
}

export function isServerConversionType(value: unknown): value is ServerConversionType {
  return typeof value === 'string'
    && Object.prototype.hasOwnProperty.call(SERVER_CONVERSION_VALUES, value);
}

export function serverEventParamsArePrivacySafe(
  eventName: string,
  params: unknown
): boolean {
  if (!isValidServerEventName(eventName)) return false;
  if (!isPlainObject(params)) return false;

  const entries = Object.entries(params);
  if (entries.length > MAX_PARAM_KEYS_PER_EVENT) return false;

  const scalarValuesAreSafe = entries.every(([key, value]) => {
    if (!isValidParamKey(key)) return false;
    if (typeof value === 'string') {
      return value.length <= MAX_PARAM_STRING_LENGTH
        && analyticsPayloadIsPrivacySafe({ [key]: value });
    }
    if (typeof value === 'number') {
      return Number.isFinite(value)
        && analyticsPayloadIsPrivacySafe({ [key]: value });
    }
    return typeof value === 'boolean'
      && analyticsPayloadIsPrivacySafe({ [key]: value });
  });
  if (!scalarValuesAreSafe) return false;

  switch (eventName) {
    case 'conversion': {
      if (!hasExactlyKeys(params, ['conversion_type', 'conversion_value'])) return false;
      const conversionType = params.conversion_type;
      return isServerConversionType(conversionType)
        && params.conversion_value === SERVER_CONVERSION_VALUES[conversionType];
    }
    case 'lesson_complete': {
      if (!hasExactlyKeys(
        params,
        ['lesson_id', 'lesson_slug', 'completion_percentage']
      )) return false;
      const lessonId = params.lesson_id;
      const lessonSlug = params.lesson_slug;
      const completionPercentage = params.completion_percentage;
      return typeof lessonId === 'number'
        && Number.isInteger(lessonId)
        && lessonId >= 0
        && lessonId < TOTAL_LESSONS
        && typeof lessonSlug === 'string'
        && getLessonById(lessonId)?.slug === lessonSlug
        && typeof completionPercentage === 'number'
        && Number.isInteger(completionPercentage)
        && ALLOWED_LESSON_COMPLETION_PERCENTAGES.has(completionPercentage);
    }
    case 'lesson_funnel_complete': {
      if (!hasExactlyKeys(params, ['total_time_minutes', 'total_lessons'])) return false;
      const totalTimeMinutes = params.total_time_minutes;
      return typeof totalTimeMinutes === 'number'
        && Number.isInteger(totalTimeMinutes)
        && totalTimeMinutes >= 0
        && totalTimeMinutes <= MAX_LESSON_FUNNEL_MINUTES
        && params.total_lessons === TOTAL_LESSONS;
    }
  }
}

export function sanitizeEventParams(params: unknown): Record<string, string | number | boolean> {
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

export type RawTrackPayload = {
  client_id: unknown;
  events: unknown;
};

export type RawEventPayload = {
  name: unknown;
  params: unknown;
};

export function serverTrackPayloadHasExactShape(value: unknown): value is RawTrackPayload {
  return isPlainObject(value) && hasExactlyKeys(value, ['client_id', 'events']);
}

export function serverEventHasExactShape(value: unknown): value is RawEventPayload {
  return isPlainObject(value) && hasExactlyKeys(value, ['name', 'params']);
}

export function isJsonContentType(value: string | null): boolean {
  const mediaType = value?.split(';', 1)[0]?.trim().toLowerCase();
  return mediaType === 'application/json';
}
