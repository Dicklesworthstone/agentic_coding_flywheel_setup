#!/usr/bin/env node
/**
 * VPS Pricing Research Script
 *
 * Automated research tool to scrape current VPS pricing from Contabo and OVH.
 * Run this periodically to verify that wizard pricing information is accurate.
 *
 * Usage: cd apps/web && node scripts/research-vps-pricing.mjs
 *
 * Prerequisites: @playwright/test must be installed (already in devDependencies)
 *
 * Output:
 * - Console: Pricing summary and comparison
 * - Screenshots: Saved to ../../research_screenshots/
 */

import { chromium } from '@playwright/test';
import { mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCREENSHOT_DIR = join(__dirname, '..', '..', '..', 'research_screenshots');
let hadResearchError = false;

function getErrorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

// Ensure screenshot directory exists
try { mkdirSync(SCREENSHOT_DIR, { recursive: true }); } catch {}

/**
 * Research Contabo VPS pricing
 */
async function researchContabo(page) {
  console.log('\n' + '='.repeat(70));
  console.log('  CONTABO VPS PRICING');
  console.log('='.repeat(70) + '\n');

  const results = { plans: [], timestamp: new Date().toISOString() };

  try {
    // Visit US site for USD pricing
    console.log('Visiting https://contabo.com/en-us/vps/ ...');
    await page.goto('https://contabo.com/en-us/vps/', { waitUntil: 'networkidle', timeout: 60000 });
    await page.waitForTimeout(3000);

    // Take screenshot
    await page.screenshot({
      path: join(SCREENSHOT_DIR, 'contabo_pricing.png'),
      fullPage: false
    });
    console.log('Screenshot: contabo_pricing.png\n');

    // Extract page text
    const pageText = await page.evaluate(() => document.body.innerText);

    // Extract all prices
    const pricePattern = /\$(\d+\.?\d*)/g;
    let match;
    const allPrices = new Set();
    while ((match = pricePattern.exec(pageText)) !== null) {
      allPrices.add('$' + match[1]);
    }
    console.log('All prices found:', [...allPrices].join(', '));

    // Parse plan blocks looking for Cloud VPS patterns
    const lines = pageText.split('\n').map(l => l.trim()).filter(l => l);

    let currentPlan = null;
    let planData = {};

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      // Look for Cloud VPS plan names
      if (line.match(/^Cloud VPS \d+$/)) {
        if (currentPlan && planData.price) {
          results.plans.push({ ...planData, name: currentPlan });
        }
        currentPlan = line;
        planData = {};
      }

      // Look for vCPU
      if (line.match(/^\d+ vCPU$/)) {
        planData.vcpu = line;
      }

      // Look for RAM
      if (line.match(/^\d+ GB RAM$/)) {
        planData.ram = line;
      }

      // Look for storage
      if (line.match(/^\d+ GB (NVMe|SSD)$/)) {
        planData.storage = line;
      }

      // Look for monthly price
      if (line.match(/^\$\d+\.\d+$/)) {
        planData.price = line;
      }
    }

    // Add last plan
    if (currentPlan && planData.price) {
      results.plans.push({ ...planData, name: currentPlan });
    }

    // Output results
    console.log('\nContabo Cloud VPS Plans (USD):');
    console.log('-'.repeat(60));
    console.log('| Plan           | vCPU | RAM     | Storage      | Price    |');
    console.log('-'.repeat(60));

    for (const plan of results.plans) {
      const name = (plan.name || '').padEnd(14);
      const vcpu = (plan.vcpu || '?').replace(' vCPU', '').padEnd(4);
      const ram = (plan.ram || '?').padEnd(7);
      const storage = (plan.storage || '?').padEnd(12);
      const price = (plan.price ? plan.price + '/mo' : '?').padEnd(8);
      console.log(`| ${name} | ${vcpu} | ${ram} | ${storage} | ${price} |`);
    }
    console.log('-'.repeat(60));

    // Take full page screenshot
    await page.screenshot({
      path: join(SCREENSHOT_DIR, 'contabo_full.png'),
      fullPage: true
    });

  } catch (error) {
    hadResearchError = true;
    console.error('Contabo error:', getErrorMessage(error));
    try {
      await page.screenshot({ path: join(SCREENSHOT_DIR, 'contabo_error.png') });
    } catch {}
  }

  return results;
}

/**
 * Research OVH VPS pricing
 */
async function researchOVH(page) {
  console.log('\n' + '='.repeat(70));
  console.log('  OVH VPS PRICING');
  console.log('='.repeat(70) + '\n');

  const results = { plans: [], timestamp: new Date().toISOString() };

  try {
    // Visit US site for USD pricing
    console.log('Visiting https://us.ovhcloud.com/vps/ ...');
    await page.goto('https://us.ovhcloud.com/vps/', { waitUntil: 'networkidle', timeout: 60000 });
    await page.waitForTimeout(3000);

    // Take screenshot
    await page.screenshot({
      path: join(SCREENSHOT_DIR, 'ovh_pricing.png'),
      fullPage: false
    });
    console.log('Screenshot: ovh_pricing.png\n');

    // Try the configurator page for detailed pricing
    console.log('Checking configurator for detailed specs...');
    await page.goto('https://us.ovhcloud.com/vps/configurator/', { waitUntil: 'networkidle', timeout: 60000 });
    await page.waitForTimeout(3000);

    await page.screenshot({
      path: join(SCREENSHOT_DIR, 'ovh_configurator.png'),
      fullPage: false
    });

    // Extract page text
    const pageText = await page.evaluate(() => document.body.innerText);

    // Parse VPS plans
    const lines = pageText.split('\n').map(l => l.trim()).filter(l => l);

    let currentPlan = null;
    let planData = {};

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      // Look for VPS plan names
      if (line.match(/^VPS-\d+$/)) {
        if (currentPlan && planData.price) {
          results.plans.push({ ...planData, name: currentPlan });
        }
        currentPlan = line;
        planData = {};
      }

      // Look for vCore
      if (line.match(/^\d+ vCore$/)) {
        planData.vcore = line;
      }

      // Look for RAM
      if (line.match(/^\d+ GB RAM$/)) {
        planData.ram = line;
      }

      // Look for storage
      if (line.match(/^\d+ GB (NVMe|SSD)/)) {
        planData.storage = line;
      }

      // Look for price
      if (line.match(/^\$\d+\.\d+$/)) {
        planData.price = line;
      }
    }

    // Add last plan
    if (currentPlan && planData.price) {
      results.plans.push({ ...planData, name: currentPlan });
    }

    // Output results
    console.log('\nOVH VPS Plans (USD):');
    console.log('-'.repeat(60));
    console.log('| Plan   | vCore | RAM     | Storage      | Price    |');
    console.log('-'.repeat(60));

    for (const plan of results.plans) {
      const name = (plan.name || '').padEnd(6);
      const vcore = (plan.vcore || '?').replace(' vCore', '').padEnd(5);
      const ram = (plan.ram || '?').padEnd(7);
      const storage = (plan.storage || '?').padEnd(12);
      const price = (plan.price ? plan.price + '/mo' : '?').padEnd(8);
      console.log(`| ${name} | ${vcore} | ${ram} | ${storage} | ${price} |`);
    }
    console.log('-'.repeat(60));

    // Take full page screenshot
    await page.screenshot({
      path: join(SCREENSHOT_DIR, 'ovh_full.png'),
      fullPage: true
    });

  } catch (error) {
    hadResearchError = true;
    console.error('OVH error:', getErrorMessage(error));
    try {
      await page.screenshot({ path: join(SCREENSHOT_DIR, 'ovh_error.png') });
    } catch {}
  }

  return results;
}

/**
 * Generate pricing comparison summary
 */
function generateSummary() {
  const date = new Date().toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric'
  });

  console.log('\n' + '='.repeat(70));
  console.log('  PRICING COMPARISON SUMMARY');
  console.log('  ' + date);
  console.log('='.repeat(70));

  console.log(`
RECOMMENDED PLANS FOR AGENT FLYWHEEL:
--------------------------------------
For 48GB RAM (RECOMMENDED for 10+ agents):
  - Contabo Cloud VPS 40: 12 vCPU, 48GB RAM, 250GB NVMe
  - OVH VPS-4: 12 vCore, 48GB RAM, 300GB NVMe

For 24GB RAM (Budget option for 5-8 agents):
  - Contabo Cloud VPS 30: 8 vCPU, 24GB RAM, 200GB NVMe
  - OVH VPS-3: 8 vCore, 24GB RAM, 200GB NVMe

NOTES:
- Prices are base monthly rates (before taxes/fees)
- Both providers offer US datacenter locations
- No 32GB RAM plan exists at either provider (jumps from 24GB to 48GB)
- Check provider sites for current exact pricing

WIZARD UPDATE CHECKLIST:
${'-'.repeat(40)}
After running this script, verify these files have accurate pricing:
  - apps/web/app/wizard/rent-vps/page.tsx
  - Any other files mentioning VPS pricing

Screenshots saved to: ${SCREENSHOT_DIR}
`);
}

/**
 * Main entry point
 */
async function main() {
  console.log('\n' + '#'.repeat(70));
  console.log('#  VPS PRICING RESEARCH');
  console.log('#  ' + new Date().toISOString());
  console.log('#'.repeat(70));

  let browser;

  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({
      viewport: { width: 1920, height: 1080 },
      locale: 'en-US',
      timezoneId: 'America/New_York'
    });
    const page = await context.newPage();

    await researchContabo(page);
    await researchOVH(page);
    generateSummary();
  } finally {
    if (browser) {
      await browser.close();
    }
  }

  if (hadResearchError) {
    console.error('\n' + '='.repeat(70));
    console.error('  RESEARCH COMPLETED WITH ERRORS');
    console.error('='.repeat(70) + '\n');
    process.exit(1);
  }

  console.log('\n' + '='.repeat(70));
  console.log('  RESEARCH COMPLETE');
  console.log('='.repeat(70) + '\n');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
