#!/usr/bin/env bun
/**
 * Fix GA4 Settings Script
 *
 * This script:
 * 1. Enables Google Signals (required for demographics)
 * 2. Extends data retention to 14 months
 * 3. Adds missing acquisition tracking dimensions
 *
 * Usage: bun run scripts/fix-ga4-settings.ts
 *
 * Requires: Application Default Credentials (gcloud auth application-default login)
 */

import { AnalyticsAdminServiceClient } from '@google-analytics/admin';

const PROPERTY_ID = '517085078';
const PROPERTY_NAME = `properties/${PROPERTY_ID}`;

const adminClient = new AnalyticsAdminServiceClient();

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

async function enableGoogleSignals(): Promise<void> {
  console.log('\n📊 Enabling Google Signals...\n');

  try {
    // Get current settings
    const [currentSettings] = await adminClient.getGoogleSignalsSettings({
      name: `${PROPERTY_NAME}/googleSignalsSettings`,
    });

    console.log(`  Current state: ${currentSettings.state}`);
    console.log(`  Current consent: ${currentSettings.consent}`);

    if (currentSettings.state === 'GOOGLE_SIGNALS_ENABLED') {
      console.log('  ✅ Google Signals is already enabled!');
      return;
    }

    // Enable Google Signals
    const [updatedSettings] = await adminClient.updateGoogleSignalsSettings({
      googleSignalsSettings: {
        name: `${PROPERTY_NAME}/googleSignalsSettings`,
        state: 'GOOGLE_SIGNALS_ENABLED',
        consent: 'GOOGLE_SIGNALS_CONSENT_CONSENTED',
      },
      updateMask: {
        paths: ['state', 'consent'],
      },
    });

    console.log(`  New state: ${updatedSettings.state}`);
    console.log(`  New consent: ${updatedSettings.consent}`);
    console.log('  ✅ Google Signals enabled successfully!');
    console.log('\n  ⚠️  It takes 24-48 hours for demographic data to start appearing.');

  } catch (error: unknown) {
    const msg = getErrorMessage(error);
    if (msg.includes('PERMISSION_DENIED')) {
      console.log('  ❌ Permission denied - you need Admin access to enable Google Signals');
      console.log('     Please enable it manually in GA4 Admin → Data Settings → Data Collection');
    } else if (msg.includes('requires user consent')) {
      console.log('  ❌ Google Signals requires user consent acknowledgment');
      console.log('     Please enable it manually in GA4 Admin → Data Settings → Data Collection');
    } else {
      console.log(`  ❌ Error: ${msg}`);
    }
  }
}

async function extendDataRetention(): Promise<void> {
  console.log('\n⏱️  Extending Data Retention...\n');

  try {
    const [currentRetention] = await adminClient.getDataRetentionSettings({
      name: `${PROPERTY_NAME}/dataRetentionSettings`,
    });

    console.log(`  Current retention: ${currentRetention.eventDataRetention}`);

    if (currentRetention.eventDataRetention === 'FOURTEEN_MONTHS') {
      console.log('  ✅ Data retention is already set to 14 months!');
      return;
    }

    const [updatedRetention] = await adminClient.updateDataRetentionSettings({
      dataRetentionSettings: {
        name: `${PROPERTY_NAME}/dataRetentionSettings`,
        eventDataRetention: 'FOURTEEN_MONTHS',
        resetUserDataOnNewActivity: true,
      },
      updateMask: {
        paths: ['event_data_retention', 'reset_user_data_on_new_activity'],
      },
    });

    console.log(`  New retention: ${updatedRetention.eventDataRetention}`);
    console.log('  ✅ Data retention extended to 14 months!');

  } catch (error: unknown) {
    const msg = getErrorMessage(error);
    console.log(`  ❌ Error: ${msg}`);
  }
}

async function addMissingDimensions(): Promise<void> {
  console.log('\n📏 Adding Missing Acquisition Dimensions...\n');

  // Get existing dimensions
  const existing = new Set<string>();
  try {
    const [dimensions] = await adminClient.listCustomDimensions({
      parent: PROPERTY_NAME,
    });
    for (const dim of dimensions || []) {
      if (dim.parameterName) {
        existing.add(dim.parameterName);
      }
    }
  } catch {
    console.log('  Note: Could not fetch existing dimensions');
  }

  const newDimensions = [
    // UTM Parameters (user-scoped for first-touch attribution)
    { name: 'utm_source', scope: 'USER', description: 'UTM source parameter' },
    { name: 'utm_medium', scope: 'USER', description: 'UTM medium parameter' },
    { name: 'utm_campaign', scope: 'USER', description: 'UTM campaign parameter' },
    { name: 'utm_term', scope: 'USER', description: 'UTM term parameter' },
    { name: 'utm_content', scope: 'USER', description: 'UTM content parameter' },

    // First-touch attribution
    { name: 'first_visit_date', scope: 'USER', description: 'Date of first visit' },
    { name: 'first_traffic_source', scope: 'USER', description: 'First traffic source' },
    { name: 'first_traffic_medium', scope: 'USER', description: 'First traffic medium' },
    { name: 'first_landing_page', scope: 'USER', description: 'First landing page URL' },

    // Latest session attribution
    { name: 'latest_traffic_source', scope: 'USER', description: 'Latest traffic source' },
    { name: 'latest_traffic_medium', scope: 'USER', description: 'Latest traffic medium' },

    // Referrer tracking
    { name: 'referrer', scope: 'EVENT', description: 'Full referrer URL' },
    { name: 'referrer_domain', scope: 'EVENT', description: 'Referrer domain only' },
    { name: 'landing_page', scope: 'EVENT', description: 'Landing page path' },

    // Visit tracking
    { name: 'visit_count', scope: 'USER', description: 'Number of visits by user' },
    { name: 'is_returning_user', scope: 'USER', description: 'Whether user has visited before' },
    { name: 'is_first_visit', scope: 'EVENT', description: 'Whether this is first visit' },

    // Platform detection
    { name: 'platform', scope: 'EVENT', description: 'Detected platform (macOS, Windows, etc.)' },
  ];

  let created = 0;
  let skipped = 0;

  for (const dim of newDimensions) {
    if (existing.has(dim.name)) {
      console.log(`  ⏭️  ${dim.name} (already exists)`);
      skipped++;
      continue;
    }

    try {
      await adminClient.createCustomDimension({
        parent: PROPERTY_NAME,
        customDimension: {
          parameterName: dim.name,
          displayName: dim.name.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
          description: dim.description,
          scope: dim.scope as 'EVENT' | 'USER',
        },
      });
      console.log(`  ✅ ${dim.name}`);
      created++;
    } catch (error: unknown) {
      const msg = getErrorMessage(error);
      if (msg.includes('already exists')) {
        console.log(`  ⏭️  ${dim.name} (already exists)`);
        skipped++;
      } else if (msg.includes('limit')) {
        console.log(`  ❌ ${dim.name}: Hit dimension limit`);
      } else {
        console.log(`  ❌ ${dim.name}: ${msg}`);
      }
    }
  }

  console.log(`\n  Created: ${created}, Skipped: ${skipped}`);
}

async function verifyConfiguration(): Promise<void> {
  console.log('\n🔍 Verifying Configuration...\n');

  try {
    // Check Google Signals
    const [signalsSettings] = await adminClient.getGoogleSignalsSettings({
      name: `${PROPERTY_NAME}/googleSignalsSettings`,
    });
    const signalsEnabled = signalsSettings.state === 'GOOGLE_SIGNALS_ENABLED';
    console.log(`  Google Signals: ${signalsEnabled ? '✅ Enabled' : '❌ Disabled'}`);

    // Check data retention
    const [retention] = await adminClient.getDataRetentionSettings({
      name: `${PROPERTY_NAME}/dataRetentionSettings`,
    });
    const retentionGood = retention.eventDataRetention === 'FOURTEEN_MONTHS';
    console.log(`  Data Retention: ${retentionGood ? '✅ 14 months' : `⚠️ ${retention.eventDataRetention}`}`);

    // Count dimensions
    const [dimensions] = await adminClient.listCustomDimensions({
      parent: PROPERTY_NAME,
    });
    console.log(`  Custom Dimensions: ${dimensions?.length || 0}`);

  } catch (error: unknown) {
    const msg = getErrorMessage(error);
    console.log(`  ❌ Error verifying: ${msg}`);
  }
}

async function printNextSteps(): Promise<void> {
  console.log('\n' + '═'.repeat(60));
  console.log('  NEXT STEPS');
  console.log('═'.repeat(60));

  console.log(`
  1. If Google Signals couldn't be enabled via API, enable manually:
     - Go to: https://analytics.google.com/analytics/web/#/p${PROPERTY_ID}/admin/datasettings/datacollection
     - Toggle ON "Google signals data collection"
     - Accept the terms

  2. Deploy the updated analytics code:
     - The analytics.ts file has been updated with acquisition tracking
     - Deploy to production to start collecting the new data

  3. Wait 24-48 hours:
     - Demographic data takes time to populate
     - New dimensions start collecting after deployment

  4. Re-run diagnostics:
     bun run scripts/diagnose-ga4-settings.ts
  `);
}

async function main() {
  console.log('═'.repeat(60));
  console.log('   FIX GA4 SETTINGS');
  console.log('═'.repeat(60));
  console.log(`\n  Property ID: ${PROPERTY_ID}`);
  console.log(`  Date: ${new Date().toISOString()}`);

  try {
    await enableGoogleSignals();
    await extendDataRetention();
    await addMissingDimensions();
    await verifyConfiguration();
    await printNextSteps();

    console.log('\n' + '═'.repeat(60));
    console.log('  ✅ Configuration updates complete!');
    console.log('═'.repeat(60) + '\n');

  } catch (error: unknown) {
    const msg = getErrorMessage(error);

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
