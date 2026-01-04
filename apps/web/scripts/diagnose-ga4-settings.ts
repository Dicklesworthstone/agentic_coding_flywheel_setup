#!/usr/bin/env bun
/**
 * GA4 Settings Diagnostic Script
 *
 * Comprehensive check of GA4 property settings to identify why
 * demographic/geographic data might be missing.
 *
 * Usage: bun run scripts/diagnose-ga4-settings.ts
 *
 * Requires: Application Default Credentials (gcloud auth application-default login)
 */

import { AnalyticsAdminServiceClient } from '@google-analytics/admin';
import { BetaAnalyticsDataClient } from '@google-analytics/data';

const PROPERTY_ID = '517085078';
const PROPERTY_NAME = `properties/${PROPERTY_ID}`;

const adminClient = new AnalyticsAdminServiceClient();
const dataClient = new BetaAnalyticsDataClient();

function printSection(title: string): void {
  console.log('\n' + '═'.repeat(60));
  console.log(`  ${title}`);
  console.log('═'.repeat(60) + '\n');
}

function printCheck(label: string, status: boolean | string, details?: string): void {
  const icon = typeof status === 'string' ? '🔍' : status ? '✅' : '❌';
  const statusText = typeof status === 'string' ? status : status ? 'ENABLED' : 'DISABLED/MISSING';
  console.log(`  ${icon} ${label}: ${statusText}`);
  if (details) {
    console.log(`     └─ ${details}`);
  }
}

async function checkPropertySettings(): Promise<void> {
  printSection('1. GA4 PROPERTY SETTINGS');

  try {
    // Get the property details
    const [property] = await adminClient.getProperty({ name: PROPERTY_NAME });

    console.log(`  Property ID: ${PROPERTY_ID}`);
    console.log(`  Display Name: ${property.displayName}`);
    console.log(`  Industry Category: ${property.industryCategory || 'Not set'}`);
    console.log(`  Time Zone: ${property.timeZone}`);
    console.log(`  Currency: ${property.currencyCode}`);
    const createTime = property.createTime;
    let createTimeStr = 'Unknown';
    if (createTime) {
      // Handle protobuf Timestamp object with seconds/nanos (seconds can be string or number)
      if ('seconds' in createTime && createTime.seconds != null) {
        const rawSeconds = createTime.seconds;
        const seconds: number = typeof rawSeconds === 'string'
          ? parseInt(rawSeconds, 10)
          : typeof rawSeconds === 'number' ? rawSeconds : NaN;
        if (!Number.isNaN(seconds)) {
          createTimeStr = new Date(seconds * 1000).toISOString();
        }
      } else if (createTime instanceof Date) {
        createTimeStr = createTime.toISOString();
      }
    }
    console.log(`  Create Time: ${createTimeStr}`);
    console.log(`  Service Level: ${property.serviceLevel}`);
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.log(`  ❌ Error fetching property: ${msg}`);
  }
}

async function checkGoogleSignals(): Promise<void> {
  printSection('2. GOOGLE SIGNALS (Required for Demographics)');

  try {
    // Check Google Signals settings
    const [signalsSettings] = await adminClient.getGoogleSignalsSettings({
      name: `${PROPERTY_NAME}/googleSignalsSettings`,
    });

    const state = signalsSettings.state;
    const consent = signalsSettings.consent;

    printCheck('Google Signals State', state === 'GOOGLE_SIGNALS_ENABLED',
      `Current state: ${state || 'UNKNOWN'}`);
    printCheck('Google Signals Consent', consent === 'GOOGLE_SIGNALS_CONSENT_CONSENTED',
      `Consent status: ${consent || 'UNKNOWN'}`);

    if (state !== 'GOOGLE_SIGNALS_ENABLED') {
      console.log('\n  ⚠️  ACTION REQUIRED:');
      console.log('     Go to GA4 Admin → Data Settings → Data Collection');
      console.log('     Enable "Google signals data collection"');
      console.log('     This is REQUIRED for demographics and interests data.');
    }
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    if (msg.includes('PERMISSION_DENIED')) {
      console.log('  ⚠️  Cannot check Google Signals (needs Admin access)');
      console.log('     Check manually: GA4 Admin → Data Settings → Data Collection');
    } else {
      console.log(`  ❌ Error: ${msg}`);
    }
  }
}

async function checkDataRetention(): Promise<void> {
  printSection('3. DATA RETENTION SETTINGS');

  try {
    const [retention] = await adminClient.getDataRetentionSettings({
      name: `${PROPERTY_NAME}/dataRetentionSettings`,
    });

    console.log(`  Event Data Retention: ${retention.eventDataRetention}`);
    console.log(`  Reset User Data On New Activity: ${retention.resetUserDataOnNewActivity}`);

    if (retention.eventDataRetention === 'TWO_MONTHS') {
      console.log('\n  ⚠️  Consider extending data retention to 14 months for better analysis');
    }
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.log(`  ❌ Error: ${msg}`);
  }
}

async function checkCustomDimensions(): Promise<void> {
  printSection('4. CUSTOM DIMENSIONS');

  try {
    const [dimensions] = await adminClient.listCustomDimensions({
      parent: PROPERTY_NAME,
    });

    console.log(`  Total Custom Dimensions: ${dimensions?.length || 0}\n`);

    // Group by scope
    const eventDims: string[] = [];
    const userDims: string[] = [];

    for (const dim of dimensions || []) {
      if (dim.scope === 'EVENT') {
        eventDims.push(dim.parameterName || '');
      } else if (dim.scope === 'USER') {
        userDims.push(dim.parameterName || '');
      }
    }

    console.log('  EVENT-scoped dimensions:');
    for (const name of eventDims.sort()) {
      console.log(`    - ${name}`);
    }

    console.log('\n  USER-scoped dimensions:');
    for (const name of userDims.sort()) {
      console.log(`    - ${name}`);
    }

    // Check for missing recommended dimensions
    const recommendedUserDims = [
      'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
      'first_visit_date', 'first_traffic_source', 'first_traffic_medium',
      'first_landing_page', 'latest_traffic_source', 'latest_traffic_medium',
      'visit_count', 'is_returning_user'
    ];

    const recommendedEventDims = [
      'referrer', 'referrer_domain', 'landing_page', 'is_first_visit', 'platform'
    ];

    const missingUserDims = recommendedUserDims.filter(d => !userDims.includes(d));
    const missingEventDims = recommendedEventDims.filter(d => !eventDims.includes(d));

    if (missingUserDims.length > 0) {
      console.log('\n  ⚠️  Missing recommended USER-scoped dimensions:');
      for (const dim of missingUserDims) {
        console.log(`    - ${dim}`);
      }
    }

    if (missingEventDims.length > 0) {
      console.log('\n  ⚠️  Missing recommended EVENT-scoped dimensions:');
      for (const dim of missingEventDims) {
        console.log(`    - ${dim}`);
      }
    }
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.log(`  ❌ Error: ${msg}`);
  }
}

async function checkGeographicData(): Promise<void> {
  printSection('5. GEOGRAPHIC DATA AVAILABILITY');

  try {
    // Query for geographic dimensions
    const [response] = await dataClient.runReport({
      property: PROPERTY_NAME,
      dateRanges: [{ startDate: '30daysAgo', endDate: 'today' }],
      dimensions: [
        { name: 'country' },
        { name: 'city' },
      ],
      metrics: [{ name: 'activeUsers' }],
      orderBys: [{ metric: { metricName: 'activeUsers' }, desc: true }],
      limit: 15,
    });

    if (response.rows && response.rows.length > 0) {
      console.log('  Geographic data IS being collected:\n');
      console.log('  Country                City                  Users');
      console.log('  ' + '─'.repeat(55));

      for (const row of response.rows) {
        const country = row.dimensionValues?.[0]?.value || '';
        const city = row.dimensionValues?.[1]?.value || '';
        const users = row.metricValues?.[0]?.value || '0';
        console.log(`  ${country.padEnd(22)} ${city.padEnd(22)} ${users.padStart(5)}`);
      }
    } else {
      console.log('  ❌ No geographic data found!');
      console.log('     This could indicate a configuration issue.');
    }
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.log(`  ❌ Error: ${msg}`);
  }
}

async function checkDemographicData(): Promise<void> {
  printSection('6. DEMOGRAPHIC DATA AVAILABILITY');

  try {
    // Query for demographic dimensions
    const [response] = await dataClient.runReport({
      property: PROPERTY_NAME,
      dateRanges: [{ startDate: '30daysAgo', endDate: 'today' }],
      dimensions: [
        { name: 'userAgeBracket' },
      ],
      metrics: [{ name: 'activeUsers' }],
      orderBys: [{ metric: { metricName: 'activeUsers' }, desc: true }],
      limit: 10,
    });

    if (response.rows && response.rows.length > 0) {
      const hasRealData = response.rows.some(row =>
        row.dimensionValues?.[0]?.value && row.dimensionValues[0].value !== '(not set)'
      );

      if (hasRealData) {
        console.log('  Demographics data IS being collected:\n');
        console.log('  Age Bracket           Users');
        console.log('  ' + '─'.repeat(30));

        for (const row of response.rows) {
          const age = row.dimensionValues?.[0]?.value || '';
          const users = row.metricValues?.[0]?.value || '0';
          console.log(`  ${age.padEnd(22)} ${users.padStart(5)}`);
        }
      } else {
        console.log('  ❌ No demographic data collected (all values are "(not set)")');
        console.log('\n  Possible causes:');
        console.log('     1. Google Signals is not enabled');
        console.log('     2. Not enough users (thresholding applied)');
        console.log('     3. Users opted out of personalization');
        console.log('     4. Data collection period too short');
      }
    } else {
      console.log('  ❌ No demographic data found!');
    }
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    if (msg.includes('not a valid dimension')) {
      console.log('  ⚠️  Demographics dimensions not available');
      console.log('     This usually means Google Signals is not enabled.');
    } else {
      console.log(`  ❌ Error: ${msg}`);
    }
  }
}

async function checkTrafficSourceData(): Promise<void> {
  printSection('7. TRAFFIC SOURCE DATA');

  try {
    const [response] = await dataClient.runReport({
      property: PROPERTY_NAME,
      dateRanges: [{ startDate: '30daysAgo', endDate: 'today' }],
      dimensions: [
        { name: 'sessionSource' },
        { name: 'sessionMedium' },
      ],
      metrics: [{ name: 'sessions' }, { name: 'activeUsers' }],
      orderBys: [{ metric: { metricName: 'sessions' }, desc: true }],
      limit: 15,
    });

    if (response.rows && response.rows.length > 0) {
      console.log('  Traffic source data:\n');
      console.log('  Source                Medium          Sessions   Users');
      console.log('  ' + '─'.repeat(58));

      for (const row of response.rows) {
        const source = row.dimensionValues?.[0]?.value || '';
        const medium = row.dimensionValues?.[1]?.value || '';
        const sessions = row.metricValues?.[0]?.value || '0';
        const users = row.metricValues?.[1]?.value || '0';
        console.log(`  ${source.padEnd(22)} ${medium.padEnd(15)} ${sessions.padStart(8)} ${users.padStart(7)}`);
      }
    }
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.log(`  ❌ Error: ${msg}`);
  }
}

async function checkDeviceData(): Promise<void> {
  printSection('8. DEVICE & TECHNOLOGY DATA');

  try {
    const [response] = await dataClient.runReport({
      property: PROPERTY_NAME,
      dateRanges: [{ startDate: '30daysAgo', endDate: 'today' }],
      dimensions: [
        { name: 'deviceCategory' },
        { name: 'operatingSystem' },
        { name: 'browser' },
      ],
      metrics: [{ name: 'activeUsers' }],
      orderBys: [{ metric: { metricName: 'activeUsers' }, desc: true }],
      limit: 15,
    });

    if (response.rows && response.rows.length > 0) {
      console.log('  Device data:\n');
      console.log('  Device      OS               Browser          Users');
      console.log('  ' + '─'.repeat(55));

      for (const row of response.rows) {
        const device = row.dimensionValues?.[0]?.value || '';
        const os = row.dimensionValues?.[1]?.value || '';
        const browser = row.dimensionValues?.[2]?.value || '';
        const users = row.metricValues?.[0]?.value || '0';
        console.log(`  ${device.padEnd(12)} ${os.padEnd(16)} ${browser.padEnd(16)} ${users.padStart(5)}`);
      }
    }
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.log(`  ❌ Error: ${msg}`);
  }
}

async function checkDataStreams(): Promise<void> {
  printSection('9. DATA STREAMS');

  try {
    const [streams] = await adminClient.listDataStreams({
      parent: PROPERTY_NAME,
    });

    for (const stream of streams || []) {
      console.log(`  Stream: ${stream.displayName}`);
      console.log(`    Type: ${stream.type}`);
      console.log(`    Name: ${stream.name}`);

      if (stream.webStreamData) {
        console.log(`    Measurement ID: ${stream.webStreamData.measurementId}`);
        console.log(`    Default URI: ${stream.webStreamData.defaultUri}`);
      }
    }
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.log(`  ❌ Error: ${msg}`);
  }
}

async function generateRecommendations(): Promise<void> {
  printSection('10. RECOMMENDATIONS');

  console.log(`  Based on the analysis, here are recommendations:

  📊 FOR DEMOGRAPHIC DATA:
     1. Enable Google Signals in GA4 Admin → Data Settings → Data Collection
     2. Wait 24-48 hours for data to populate
     3. Ensure you have sufficient traffic (demographics apply thresholding)

  🌍 FOR GEOGRAPHIC DATA:
     Geographic data should be collected automatically if the GA4 tag
     is properly configured. Check that:
     - The gtag.js script is loading correctly
     - No ad blockers are interfering in testing
     - The site has actual visitors (not just your own testing)

  📈 FOR ACQUISITION/UTM DATA:
     Add user-scoped custom dimensions for:
     - utm_source, utm_medium, utm_campaign, utm_term, utm_content
     - first_traffic_source, first_traffic_medium
     - referrer, referrer_domain
     - first_visit_date, landing_page

     Then update analytics.ts to track these on session_start

  🔧 NEXT STEPS:
     1. Run: bun run scripts/configure-ga4.ts (adds missing dimensions)
     2. Verify Google Signals is enabled in GA4 Admin UI
     3. Wait 24-48 hours for data to accumulate
     4. Re-run this diagnostic to verify improvements
  `);
}

async function main() {
  console.log('═'.repeat(60));
  console.log('   GA4 SETTINGS DIAGNOSTIC REPORT');
  console.log('═'.repeat(60));
  console.log(`\n  Property ID: ${PROPERTY_ID}`);
  console.log(`  Date: ${new Date().toISOString()}`);

  try {
    await checkPropertySettings();
    await checkGoogleSignals();
    await checkDataRetention();
    await checkDataStreams();
    await checkCustomDimensions();
    await checkGeographicData();
    await checkDemographicData();
    await checkTrafficSourceData();
    await checkDeviceData();
    await generateRecommendations();

    console.log('\n' + '═'.repeat(60));
    console.log('  ✅ Diagnostic complete!');
    console.log('═'.repeat(60) + '\n');

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);

    if (msg.includes('Could not load the default credentials')) {
      console.error('\n❌ Authentication required!');
      console.error('\nPlease run:');
      console.error('  gcloud auth application-default login');
      console.error('\nThen retry this script.');
    } else {
      console.error('\n❌ Error:', msg);
    }
    process.exit(1);
  }
}

main().catch(console.error);
