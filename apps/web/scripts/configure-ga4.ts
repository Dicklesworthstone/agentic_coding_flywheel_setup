#!/usr/bin/env bun
/**
 * GA4 Configuration Script
 *
 * Configures Google Analytics 4 with custom dimensions, conversions, and audiences
 * tailored for the ACFS wizard funnel and learning hub tracking.
 *
 * Usage: bun run scripts/configure-ga4.ts
 *
 * Requires: Application Default Credentials (gcloud auth application-default login)
 */

import { AnalyticsAdminServiceClient } from '@google-analytics/admin';
import type { google } from '@google-analytics/admin/build/protos/protos';

const PROPERTY_ID = '517085078';

// Type-safe error message extraction
function getErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

const PROPERTY_NAME = `properties/${PROPERTY_ID}`;

// Initialize the client (uses ADC automatically)
const adminClient = new AnalyticsAdminServiceClient();

// Custom dimensions to create
// NOTE: Parameter names must EXACTLY match what the analytics.ts code sends in events
const CUSTOM_DIMENSIONS = [
  // Wizard/Funnel step tracking - these match the actual event parameters
  { name: 'step_number', scope: 'EVENT', description: 'Step number (1-13 for wizard)' },
  { name: 'step_name', scope: 'EVENT', description: 'Step name (e.g., os_selection, rent_vps)' },
  { name: 'step_title', scope: 'EVENT', description: 'Human-readable step title' },
  { name: 'previous_step', scope: 'EVENT', description: 'Previous step number' },
  { name: 'is_new_max_step', scope: 'EVENT', description: 'Whether this is furthest step reached' },
  { name: 'total_steps', scope: 'EVENT', description: 'Total number of steps in funnel' },
  { name: 'progress_percentage', scope: 'EVENT', description: 'Progress through funnel (0-100%)' },
  { name: 'completed_steps_count', scope: 'EVENT', description: 'Number of steps completed' },

  // Legacy wizard dimensions (kept for backwards compatibility)
  { name: 'wizard_step', scope: 'EVENT', description: '[Legacy] Current wizard step name' },
  { name: 'wizard_step_number', scope: 'EVENT', description: '[Legacy] Wizard step number' },
  { name: 'wizard_step_title', scope: 'EVENT', description: '[Legacy] Human-readable wizard step title' },

  // Lesson tracking
  { name: 'lesson_id', scope: 'EVENT', description: 'Lesson ID (0-19)' },
  { name: 'lesson_slug', scope: 'EVENT', description: 'Lesson URL slug' },
  { name: 'lesson_title', scope: 'EVENT', description: 'Lesson title' },

  // Funnel tracking
  { name: 'funnel_id', scope: 'EVENT', description: 'Unique funnel session ID' },
  { name: 'funnel_source', scope: 'USER', description: 'Traffic source when funnel started' },
  { name: 'funnel_medium', scope: 'USER', description: 'Traffic medium when funnel started' },
  { name: 'funnel_campaign', scope: 'USER', description: 'Campaign when funnel started' },
  { name: 'milestone', scope: 'EVENT', description: 'Funnel milestone name' },

  // Progress tracking
  { name: 'completion_percentage', scope: 'EVENT', description: 'Progress through funnel (0-100%)' },
  { name: 'max_step_reached', scope: 'EVENT', description: 'Highest step/lesson reached in session' },
  // NOTE: completed_count is registered but not currently used in analytics.ts
  // Consider using completed_steps_count instead, or add events that send this parameter
  { name: 'completed_count', scope: 'EVENT', description: 'Number of steps/lessons completed' },

  // Context
  { name: 'is_returning', scope: 'EVENT', description: 'Whether user is returning to a previous step' },
  { name: 'dropoff_reason', scope: 'EVENT', description: 'Reason for funnel abandonment' },
  { name: 'selected_os', scope: 'USER', description: 'OS selected in wizard (mac/windows/linux)' },
  { name: 'vps_provider', scope: 'USER', description: 'VPS provider selected' },
  { name: 'terminal_app', scope: 'USER', description: 'Terminal application selected' },

  // Time tracking
  { name: 'time_from_previous_step_seconds', scope: 'EVENT', description: 'Seconds since previous step' },
  // Note: time_on_step_seconds is defined as a metric (not dimension) since it's a numeric value
];

// Custom metrics to create
const CUSTOM_METRICS = [
  { name: 'time_on_step_seconds', scope: 'EVENT', description: 'Time spent on wizard step in seconds', measurementUnit: 'SECONDS' },
  { name: 'time_on_lesson_seconds', scope: 'EVENT', description: 'Time spent on lesson in seconds', measurementUnit: 'SECONDS' },
  { name: 'time_from_previous_seconds', scope: 'EVENT', description: 'Time since previous step/lesson', measurementUnit: 'SECONDS' },
  { name: 'total_funnel_time_seconds', scope: 'EVENT', description: 'Total time in funnel', measurementUnit: 'SECONDS' },
];

// Events to mark as conversions
const CONVERSION_EVENTS = [
  'wizard_start',           // User started the wizard
  'wizard_complete',        // User completed entire wizard
  'vps_created',           // User reached VPS creation step
  'installer_run',         // User ran the installer
  'learning_hub_started',  // User started learning hub
  'lesson_funnel_complete', // User completed all lessons
  'conversion',            // Generic conversion event
];

async function getExistingCustomDimensions(): Promise<Set<string>> {
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
    console.log('Note: Could not fetch existing dimensions (might not have permission)');
  }
  return existing;
}

async function getExistingCustomMetrics(): Promise<Set<string>> {
  const existing = new Set<string>();
  try {
    const [metrics] = await adminClient.listCustomMetrics({
      parent: PROPERTY_NAME,
    });
    for (const metric of metrics || []) {
      if (metric.parameterName) {
        existing.add(metric.parameterName);
      }
    }
  } catch {
    console.log('Note: Could not fetch existing metrics (might not have permission)');
  }
  return existing;
}

async function createCustomDimensions() {
  console.log('\n📊 Creating Custom Dimensions...\n');

  const existing = await getExistingCustomDimensions();
  let created = 0;
  let skipped = 0;

  for (const dim of CUSTOM_DIMENSIONS) {
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
      const message = getErrorMessage(error);
      if (message.includes('already exists')) {
        console.log(`  ⏭️  ${dim.name} (already exists)`);
        skipped++;
      } else {
        console.log(`  ❌ ${dim.name}: ${message}`);
      }
    }
  }

  console.log(`\n  Created: ${created}, Skipped: ${skipped}`);
}

async function createCustomMetrics() {
  console.log('\n📈 Creating Custom Metrics...\n');

  const existing = await getExistingCustomMetrics();
  let created = 0;
  let skipped = 0;

  for (const metric of CUSTOM_METRICS) {
    if (existing.has(metric.name)) {
      console.log(`  ⏭️  ${metric.name} (already exists)`);
      skipped++;
      continue;
    }

    try {
      await adminClient.createCustomMetric({
        parent: PROPERTY_NAME,
        customMetric: {
          parameterName: metric.name,
          displayName: metric.name.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
          description: metric.description,
          scope: metric.scope as 'EVENT',
          measurementUnit: metric.measurementUnit as 'SECONDS',
        },
      });
      console.log(`  ✅ ${metric.name}`);
      created++;
    } catch (error: unknown) {
      const message = getErrorMessage(error);
      if (message.includes('already exists')) {
        console.log(`  ⏭️  ${metric.name} (already exists)`);
        skipped++;
      } else {
        console.log(`  ❌ ${metric.name}: ${message}`);
      }
    }
  }

  console.log(`\n  Created: ${created}, Skipped: ${skipped}`);
}

async function markConversionEvents() {
  console.log('\n🎯 Marking Conversion Events...\n');

  let marked = 0;
  let skipped = 0;

  for (const eventName of CONVERSION_EVENTS) {
    try {
      // First, try to get the existing conversion event
      try {
        await adminClient.getConversionEvent({
          name: `${PROPERTY_NAME}/conversionEvents/${eventName}`,
        });
        console.log(`  ⏭️  ${eventName} (already a conversion)`);
        skipped++;
        continue;
      } catch {
        // Doesn't exist, create it
      }

      await adminClient.createConversionEvent({
        parent: PROPERTY_NAME,
        conversionEvent: {
          eventName: eventName,
        },
      });
      console.log(`  ✅ ${eventName}`);
      marked++;
    } catch (error: unknown) {
      const message = getErrorMessage(error);
      if (message.includes('already exists') || message.includes('ALREADY_EXISTS')) {
        console.log(`  ⏭️  ${eventName} (already a conversion)`);
        skipped++;
      } else {
        console.log(`  ❌ ${eventName}: ${message}`);
      }
    }
  }

  console.log(`\n  Marked: ${marked}, Skipped: ${skipped}`);
}

async function createAudiences() {
  console.log('\n👥 Creating Audiences...\n');

  const audiences = [
    {
      displayName: 'Wizard Started - Not Completed',
      description: 'Users who started the wizard but did not complete it',
      membershipDurationDays: 30,
      filterClauses: [
        {
          clauseType: 'INCLUDE',
          simpleFilter: {
            scope: 'AUDIENCE_FILTER_SCOPE_ACROSS_ALL_SESSIONS',
            filterExpression: {
              andGroup: {
                filterExpressions: [
                  {
                    orGroup: {
                      filterExpressions: [
                        {
                          dimensionOrMetricFilter: {
                            fieldName: 'eventName',
                            stringFilter: {
                              matchType: 'EXACT',
                              value: 'wizard_start',
                            },
                          },
                        },
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
        {
          clauseType: 'EXCLUDE',
          simpleFilter: {
            scope: 'AUDIENCE_FILTER_SCOPE_ACROSS_ALL_SESSIONS',
            filterExpression: {
              orGroup: {
                filterExpressions: [
                  {
                    dimensionOrMetricFilter: {
                      fieldName: 'eventName',
                      stringFilter: {
                        matchType: 'EXACT',
                        value: 'wizard_complete',
                      },
                    },
                  },
                ],
              },
            },
          },
        },
      ],
    },
    {
      displayName: 'Wizard Completed',
      description: 'Users who completed the entire setup wizard',
      membershipDurationDays: 90,
      filterClauses: [
        {
          clauseType: 'INCLUDE',
          simpleFilter: {
            scope: 'AUDIENCE_FILTER_SCOPE_ACROSS_ALL_SESSIONS',
            filterExpression: {
              orGroup: {
                filterExpressions: [
                  {
                    dimensionOrMetricFilter: {
                      fieldName: 'eventName',
                      stringFilter: {
                        matchType: 'EXACT',
                        value: 'wizard_complete',
                      },
                    },
                  },
                ],
              },
            },
          },
        },
      ],
    },
    {
      displayName: 'Learning Hub Active',
      description: 'Users actively engaged with the learning hub',
      membershipDurationDays: 30,
      filterClauses: [
        {
          clauseType: 'INCLUDE',
          simpleFilter: {
            scope: 'AUDIENCE_FILTER_SCOPE_ACROSS_ALL_SESSIONS',
            filterExpression: {
              orGroup: {
                filterExpressions: [
                  {
                    dimensionOrMetricFilter: {
                      fieldName: 'eventName',
                      stringFilter: {
                        matchType: 'EXACT',
                        value: 'lesson_complete',
                      },
                    },
                  },
                ],
              },
            },
          },
        },
      ],
    },
    {
      displayName: 'All Lessons Completed',
      description: 'Users who completed all learning hub lessons',
      membershipDurationDays: 540,
      filterClauses: [
        {
          clauseType: 'INCLUDE',
          simpleFilter: {
            scope: 'AUDIENCE_FILTER_SCOPE_ACROSS_ALL_SESSIONS',
            filterExpression: {
              orGroup: {
                filterExpressions: [
                  {
                    dimensionOrMetricFilter: {
                      fieldName: 'eventName',
                      stringFilter: {
                        matchType: 'EXACT',
                        value: 'lesson_funnel_complete',
                      },
                    },
                  },
                ],
              },
            },
          },
        },
      ],
    },
  ];

  let created = 0;
  let skipped = 0;

  for (const audience of audiences) {
    try {
      await adminClient.createAudience({
        parent: PROPERTY_NAME,
        audience: audience as google.analytics.admin.v1alpha.IAudience,
      });
      console.log(`  ✅ ${audience.displayName}`);
      created++;
    } catch (error: unknown) {
      const message = getErrorMessage(error);
      if (message.includes('already exists') || message.includes('ALREADY_EXISTS')) {
        console.log(`  ⏭️  ${audience.displayName} (already exists)`);
        skipped++;
      } else {
        console.log(`  ❌ ${audience.displayName}: ${message}`);
      }
    }
  }

  console.log(`\n  Created: ${created}, Skipped: ${skipped}`);
}

async function printSummary() {
  console.log('\n' + '═'.repeat(60));
  console.log('📋 GA4 CONFIGURATION SUMMARY');
  console.log('═'.repeat(60));
  console.log(`
Property ID: ${PROPERTY_ID}

✅ Custom Dimensions: Track wizard steps, lessons, funnels, and user choices
✅ Custom Metrics: Track time spent on steps and lessons
✅ Conversion Events: Key milestones marked for conversion tracking
✅ Audiences: Segments for retargeting and analysis

NEXT STEPS:
1. Wait 24-48 hours for data to accumulate in GA4
2. Go to GA4 → Reports → Engagement → Events to see custom events
3. Go to GA4 → Explore to create custom funnel visualizations
4. Use the pre-built audiences in GA4 → Admin → Audiences

RECOMMENDED EXPLORATIONS TO CREATE:
1. Wizard Funnel: funnel_step_enter events by step_number
2. Learning Hub Funnel: lesson_view events by lesson_id
3. User Journey: Path exploration from landing to conversion

VIEW YOUR GA4:
https://analytics.google.com/analytics/web/#/p${PROPERTY_ID}/reports/intelligenthome
`);
}

async function main() {
  console.log('═'.repeat(60));
  console.log('🔧 ACFS GA4 Configuration Script');
  console.log('═'.repeat(60));
  console.log(`\nConfiguring GA4 Property: ${PROPERTY_ID}\n`);

  try {
    await createCustomDimensions();
    await createCustomMetrics();
    await markConversionEvents();
    await createAudiences();
    await printSummary();

    console.log('\n✅ GA4 configuration complete!\n');
  } catch (error: unknown) {
    console.error('\n❌ Configuration failed:', getErrorMessage(error));
    console.error('\nMake sure you have:');
    console.error('1. Run: gcloud auth application-default login');
    console.error('2. Enabled the Google Analytics Admin API in your GCP project');
    console.error('3. Have Editor access to the GA4 property');
    process.exit(1);
  }
}

main();
