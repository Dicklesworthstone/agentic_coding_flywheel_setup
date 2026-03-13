#!/usr/bin/env bun
/**
 * Debug GA4 Events - Check what events are actually being tracked
 */

import { BetaAnalyticsDataClient } from '@google-analytics/data';

const PROPERTY_ID = '517085078';
const client = new BetaAnalyticsDataClient();
let hadOperationalError = false;

function recordOperationalError(context: string, error: unknown): void {
  hadOperationalError = true;
  const message = error instanceof Error ? error.message : String(error);
  console.error(`  ❌ ${context}: ${message}`);
}

async function listAllEvents(): Promise<void> {
  console.log('\n📋 All Events (Last 30 Days):\n');

  try {
    const [response] = await client.runReport({
      property: `properties/${PROPERTY_ID}`,
      dateRanges: [{ startDate: '30daysAgo', endDate: 'today' }],
      dimensions: [{ name: 'eventName' }],
      metrics: [{ name: 'eventCount' }, { name: 'activeUsers' }],
      orderBys: [{ metric: { metricName: 'eventCount' }, desc: true }],
      limit: 50,
    });

    console.log('  Event Name                    Count    Users');
    console.log('  ' + '─'.repeat(50));

    for (const row of response.rows || []) {
      const name = row.dimensionValues?.[0]?.value || '';
      const count = row.metricValues?.[0]?.value || '0';
      const users = row.metricValues?.[1]?.value || '0';
      console.log(`  ${name.padEnd(30)} ${count.padStart(6)}    ${users.padStart(5)}`);
    }
  } catch (error: unknown) {
    recordOperationalError('Error listing events', error);
  }
}

async function checkCustomDimensions(): Promise<void> {
  console.log('\n📊 Custom Dimensions Check:\n');

  const dimensionsToCheck = [
    'customEvent:wizard_step_number',
    'customEvent:wizard_step',
    'customEvent:lesson_id',
    'customEvent:step_number',
  ];

  for (const dim of dimensionsToCheck) {
    console.log(`  Checking ${dim}...`);
    try {
      const [response] = await client.runReport({
        property: `properties/${PROPERTY_ID}`,
        dateRanges: [{ startDate: '30daysAgo', endDate: 'today' }],
        dimensions: [{ name: dim }],
        metrics: [{ name: 'eventCount' }],
        limit: 10,
      });

      if (response.rows && response.rows.length > 0) {
        console.log(`    ✅ Has data: ${response.rows.length} unique values`);
        for (const row of response.rows.slice(0, 5)) {
          console.log(`       - ${row.dimensionValues?.[0]?.value}: ${row.metricValues?.[0]?.value} events`);
        }
      } else {
        console.log(`    ❌ No data found`);
      }
    } catch (error: unknown) {
      const msg = error instanceof Error ? error.message : String(error);
      if (msg.includes('not a valid dimension')) {
        console.log(`    ❌ Dimension not registered`);
      } else {
        hadOperationalError = true;
        console.log(`    ❌ Error: ${msg.slice(0, 80)}`);
      }
    }
  }
}

async function checkFunnelEvents(): Promise<void> {
  console.log('\n🔍 Funnel-Related Events:\n');

  const eventsToCheck = [
    'funnel_step_enter',
    'funnel_step_complete',
    'wizard_step_view',
    'wizard_step_complete',
    'lesson_view',
    'lesson_complete',
    'lesson_enter',
  ];

  for (const eventName of eventsToCheck) {
    try {
      const [response] = await client.runReport({
        property: `properties/${PROPERTY_ID}`,
        dateRanges: [{ startDate: '30daysAgo', endDate: 'today' }],
        dimensions: [{ name: 'eventName' }],
        metrics: [{ name: 'eventCount' }, { name: 'activeUsers' }],
        dimensionFilter: {
          filter: {
            fieldName: 'eventName',
            stringFilter: { matchType: 'EXACT', value: eventName },
          },
        },
      });

      if (response.rows && response.rows.length > 0) {
        const count = response.rows[0].metricValues?.[0]?.value || '0';
        const users = response.rows[0].metricValues?.[1]?.value || '0';
        console.log(`  ✅ ${eventName.padEnd(25)} ${count.padStart(6)} events, ${users.padStart(5)} users`);
      } else {
        console.log(`  ❌ ${eventName.padEnd(25)} No data`);
      }
    } catch (error: unknown) {
      hadOperationalError = true;
      const msg = error instanceof Error ? error.message : String(error);
      console.log(`  ❌ ${eventName.padEnd(25)} ${msg.slice(0, 60)}`);
    }
  }
}

async function checkPageViews(): Promise<void> {
  console.log('\n📄 Page Views by Path:\n');

  try {
    const [response] = await client.runReport({
      property: `properties/${PROPERTY_ID}`,
      dateRanges: [{ startDate: '30daysAgo', endDate: 'today' }],
      dimensions: [{ name: 'pagePath' }],
      metrics: [{ name: 'screenPageViews' }, { name: 'activeUsers' }],
      orderBys: [{ metric: { metricName: 'screenPageViews' }, desc: true }],
      limit: 20,
    });

    console.log('  Path                                      Views   Users');
    console.log('  ' + '─'.repeat(55));

    for (const row of response.rows || []) {
      const path = row.dimensionValues?.[0]?.value || '';
      const views = row.metricValues?.[0]?.value || '0';
      const users = row.metricValues?.[1]?.value || '0';
      console.log(`  ${path.padEnd(40).slice(0, 40)} ${views.padStart(6)}  ${users.padStart(6)}`);
    }
  } catch (error: unknown) {
    recordOperationalError('Error checking page views', error);
  }
}

async function main() {
  console.log('═'.repeat(60));
  console.log('🔍 GA4 Debug Report');
  console.log('═'.repeat(60));

  await listAllEvents();
  await checkCustomDimensions();
  await checkFunnelEvents();
  await checkPageViews();

  if (hadOperationalError) {
    console.error('\n⚠️ Debug report completed with errors.');
    process.exit(1);
  }

  console.log('\n═'.repeat(60));
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
