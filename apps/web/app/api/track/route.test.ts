import { describe, expect, test } from 'bun:test';
import {
  isJsonContentType,
  isValidServerEventName,
  serverEventParamsArePrivacySafe,
  serverUserPropertiesArePrivacySafe,
} from './route';

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

  test('refuses sensitive or lossy event parameters before GA4 forwarding', () => {
    const credential = ['ghp_', 'A1'.repeat(12)].join('');

    expect(serverEventParamsArePrivacySafe({
      conversion_type: 'wizard_start',
      conversion_value: 1,
    })).toBe(true);
    expect(serverEventParamsArePrivacySafe({ vps_ip: 'example.invalid' })).toBe(false);
    expect(serverEventParamsArePrivacySafe({ note: 'server 203.0.113.42' })).toBe(false);
    expect(serverEventParamsArePrivacySafe({ note: credential })).toBe(false);
    expect(serverEventParamsArePrivacySafe({
      note: 'x'.repeat(301),
    })).toBe(false);
    expect(serverEventParamsArePrivacySafe({ nested: { ignored: credential } })).toBe(false);
  });

  test('validates user-property wrappers and their privacy content', () => {
    expect(serverUserPropertiesArePrivacySafe({
      user_tier: { value: 'beginner' },
    })).toBe(true);
    expect(serverUserPropertiesArePrivacySafe({
      host: { value: 'production' },
    })).toBe(false);
    expect(serverUserPropertiesArePrivacySafe({
      cohort: { value: 'server 2001:db8::42' },
    })).toBe(false);
    expect(serverUserPropertiesArePrivacySafe({
      cohort: { value: 'beginner', ignored: 'extra' },
    })).toBe(false);
  });
});
