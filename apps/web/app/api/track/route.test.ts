import { describe, expect, test } from 'bun:test';
import {
  isJsonContentType,
  isValidClientId,
  isValidServerEventName,
  serverEventHasExactShape,
  serverEventParamsArePrivacySafe,
  serverTrackPayloadHasExactShape,
} from './route';
import { TOTAL_LESSONS } from '@/lib/lessons';

describe('server analytics trust boundary', () => {
  test('accepts only the application/json media type', () => {
    expect(isJsonContentType('application/json')).toBe(true);
    expect(isJsonContentType('Application/JSON; charset=utf-8')).toBe(true);
    expect(isJsonContentType('text/application/json')).toBe(false);
    expect(isJsonContentType('application/jsonp')).toBe(false);
    expect(isJsonContentType(null)).toBe(false);
  });

  test('allows only server events emitted by the checked-in analytics client', () => {
    expect(isValidServerEventName('conversion')).toBe(true);
    expect(isValidServerEventName('lesson_complete')).toBe(true);
    expect(isValidServerEventName('lesson_funnel_complete')).toBe(true);
    expect(isValidServerEventName('arbitrary_probe')).toBe(false);
    expect(isValidServerEventName('Conversion')).toBe(false);
  });

  test('accepts only the numeric client ID grammar emitted by the client', () => {
    expect(isValidClientId('0123456789.1787596778')).toBe(true);
    expect(isValidClientId('legacy-client_id')).toBe(false);
    expect(isValidClientId('ghp_A1A1A1A1A1A1A1A1A1A1A1A1')).toBe(false);
  });

  test('enforces exact request and event object keys', () => {
    expect(serverTrackPayloadHasExactShape({
      client_id: '0123456789.1787596778',
      events: [],
    })).toBe(true);
    expect(serverTrackPayloadHasExactShape({
      client_id: '0123456789.1787596778',
      events: [],
      user_id: 'unexpected-surface',
    })).toBe(false);
    expect(serverEventHasExactShape({
      name: 'conversion',
      params: {},
    })).toBe(true);
    expect(serverEventHasExactShape({
      name: 'conversion',
      params: {},
      debug: true,
    })).toBe(false);
  });

  test('enforces the exact parameter schema for each server event', () => {
    const firstCompletionPercentage = Math.round((1 / TOTAL_LESSONS) * 100);

    expect(serverEventParamsArePrivacySafe('conversion', {
      conversion_type: 'wizard_start',
      conversion_value: 0,
    })).toBe(true);
    expect(serverEventParamsArePrivacySafe('lesson_complete', {
      lesson_id: 0,
      lesson_slug: 'welcome',
      completion_percentage: firstCompletionPercentage,
    })).toBe(true);
    expect(serverEventParamsArePrivacySafe('lesson_funnel_complete', {
      total_time_minutes: 12,
      total_lessons: TOTAL_LESSONS,
    })).toBe(true);

    expect(serverEventParamsArePrivacySafe('conversion', {
      conversion_type: 'wizard_start',
      conversion_value: 1,
    })).toBe(false);
    expect(serverEventParamsArePrivacySafe('conversion', {
      conversion_type: 'wizard_start',
      conversion_value: 0,
      lesson_id: 0,
    })).toBe(false);
    expect(serverEventParamsArePrivacySafe('lesson_complete', {
      lesson_id: 0,
      lesson_slug: 'linux-basics',
      completion_percentage: firstCompletionPercentage,
    })).toBe(false);
    expect(serverEventParamsArePrivacySafe('lesson_complete', {
      lesson_id: 0,
      lesson_slug: 'welcome',
      completion_percentage: -1,
    })).toBe(false);
    expect(serverEventParamsArePrivacySafe('lesson_funnel_complete', {
      total_time_minutes: 12,
      total_lessons: TOTAL_LESSONS + 1,
    })).toBe(false);
    expect(serverEventParamsArePrivacySafe('arbitrary_probe', {})).toBe(false);
  });

  test('refuses sensitive or lossy event parameters before GA4 forwarding', () => {
    const credential = ['ghp_', 'A1'.repeat(12)].join('');

    expect(serverEventParamsArePrivacySafe('conversion', {
      conversion_type: 'wizard_start',
      conversion_value: 0,
    })).toBe(true);
    expect(serverEventParamsArePrivacySafe('conversion', {
      conversion_type: 'wizard_start',
      conversion_value: 0,
      vps_ip: 'example.invalid',
    })).toBe(false);
    expect(serverEventParamsArePrivacySafe('lesson_complete', {
      lesson_id: 0,
      lesson_slug: `welcome-${credential}`,
      completion_percentage: Math.round((1 / TOTAL_LESSONS) * 100),
    })).toBe(false);
  });
});
