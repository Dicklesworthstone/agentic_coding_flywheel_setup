/**
 * Flywheel.ts Unit Tests
 *
 * Comprehensive tests for the flywheel data structures and helper functions.
 * Validates data integrity, type correctness, and function behavior.
 */

import { describe, test, expect } from 'bun:test';
import {
  flywheelTools,
  workflowScenarios,
  agentPrompts,
  synergyExplanations,
  flywheelDescription,
  getToolSynergy,
  getToolsBySynergy,
  getAllConnections,
  getPromptsByCategory,
  getScenarioById,
} from './flywheel';

// ============================================================
// DATA STRUCTURE TESTS
// ============================================================

describe('flywheelTools array', () => {
  test('has 10+ tools', () => {
    expect(flywheelTools.length).toBeGreaterThanOrEqual(10);
  });

  test('each tool has required fields', () => {
    for (const tool of flywheelTools) {
      expect(tool.id).toBeDefined();
      expect(tool.name).toBeDefined();
      expect(tool.shortName).toBeDefined();
      expect(tool.href).toBeDefined();
      expect(tool.icon).toBeDefined();
      expect(tool.color).toBeDefined();
      expect(tool.tagline).toBeDefined();
      expect(tool.description).toBeDefined();
      expect(tool.deepDescription).toBeDefined();
      expect(tool.connectsTo).toBeDefined();
      expect(tool.connectionDescriptions).toBeDefined();
      expect(tool.features).toBeDefined();
      expect(tool.language).toBeDefined();
    }
  });

  test('each tool has unique id', () => {
    const ids = flywheelTools.map((t) => t.id);
    const uniqueIds = new Set(ids);
    expect(uniqueIds.size).toBe(ids.length);
  });

  test('each tool has valid href', () => {
    for (const tool of flywheelTools) {
      // Most tools link to GitHub, but some (like JFP) link to their own sites
      expect(tool.href).toMatch(/^https:\/\//);
    }
  });

  test('connectsTo references valid tool ids', () => {
    const toolIds = new Set(flywheelTools.map((t) => t.id));
    for (const tool of flywheelTools) {
      for (const connectedId of tool.connectsTo) {
        if (!toolIds.has(connectedId)) {
          console.error(`Tool "${tool.id}" connects to invalid ID: "${connectedId}"`);
        }
        expect(toolIds.has(connectedId)).toBe(true);
      }
    }
  });

  test('connectionDescriptions keys match connectsTo', () => {
    for (const tool of flywheelTools) {
      const connectsToSet = new Set(tool.connectsTo);
      for (const key of Object.keys(tool.connectionDescriptions)) {
        expect(connectsToSet.has(key)).toBe(true);
      }
    }
  });

  test('features array is non-empty', () => {
    for (const tool of flywheelTools) {
      expect(tool.features.length).toBeGreaterThan(0);
    }
  });

  test('RU tool exists and has correct data', () => {
    const ru = flywheelTools.find((t) => t.id === 'ru');
    expect(ru).toBeDefined();
    expect(ru?.name).toBe('Repo Updater');
    expect(ru?.shortName).toBe('RU');
    expect(ru?.language).toBe('Bash');
    expect(ru?.connectsTo).toContain('ntm');
    expect(ru?.connectsTo).toContain('mail');
    expect(ru?.connectsTo).toContain('bv');
  });

  test('DCG tool exists and has correct data', () => {
    const dcg = flywheelTools.find((t) => t.id === 'dcg');
    expect(dcg).toBeDefined();
    expect(dcg?.name).toBe('Destructive Command Guard');
    expect(dcg?.shortName).toBe('DCG');
    expect(dcg?.language).toBe('Rust');
  });
});

describe('workflowScenarios array', () => {
  test('has multiple scenarios', () => {
    expect(workflowScenarios.length).toBeGreaterThan(0);
  });

  test('each scenario has required fields', () => {
    for (const scenario of workflowScenarios) {
      expect(scenario.id).toBeDefined();
      expect(scenario.title).toBeDefined();
      expect(scenario.description).toBeDefined();
      expect(scenario.steps).toBeDefined();
      expect(scenario.outcome).toBeDefined();
      expect(scenario.timeframe).toBeDefined();
    }
  });

  test('each scenario has unique id', () => {
    const ids = workflowScenarios.map((s) => s.id);
    const uniqueIds = new Set(ids);
    expect(uniqueIds.size).toBe(ids.length);
  });

  test('scenario steps reference valid tools', () => {
    const toolIds = new Set(flywheelTools.map((t) => t.id));
    for (const scenario of workflowScenarios) {
      for (const step of scenario.steps) {
        expect(toolIds.has(step.tool)).toBe(true);
      }
    }
  });

  test('scenario steps have required fields', () => {
    for (const scenario of workflowScenarios) {
      for (const step of scenario.steps) {
        expect(step.tool).toBeDefined();
        expect(step.action).toBeDefined();
        expect(step.result).toBeDefined();
      }
    }
  });

  test('RU scenarios exist', () => {
    const ruScenarios = workflowScenarios.filter((s) =>
      s.steps.some((step) => step.tool === 'ru')
    );
    expect(ruScenarios.length).toBeGreaterThan(0);
  });
});

describe('agentPrompts array', () => {
  test('has multiple prompts', () => {
    expect(agentPrompts.length).toBeGreaterThan(0);
  });

  test('each prompt has required fields', () => {
    for (const prompt of agentPrompts) {
      expect(prompt.id).toBeDefined();
      expect(prompt.title).toBeDefined();
      expect(prompt.category).toBeDefined();
      expect(prompt.prompt).toBeDefined();
      expect(prompt.whenToUse).toBeDefined();
      expect(prompt.bestWith).toBeDefined();
    }
  });

  test('each prompt has unique id', () => {
    const ids = agentPrompts.map((p) => p.id);
    const uniqueIds = new Set(ids);
    expect(uniqueIds.size).toBe(ids.length);
  });

  test('prompts cover all categories', () => {
    const categories = new Set(agentPrompts.map((p) => p.category));
    expect(categories.has('exploration')).toBe(true);
    expect(categories.has('review')).toBe(true);
    expect(categories.has('improvement')).toBe(true);
    expect(categories.has('planning')).toBe(true);
    expect(categories.has('execution')).toBe(true);
  });

  test('bestWith references valid tools', () => {
    const toolIds = new Set(flywheelTools.map((t) => t.id));
    for (const prompt of agentPrompts) {
      for (const toolId of prompt.bestWith) {
        expect(toolIds.has(toolId)).toBe(true);
      }
    }
  });
});

describe('synergyExplanations array', () => {
  test('has multiple synergies', () => {
    expect(synergyExplanations.length).toBeGreaterThan(0);
  });

  test('each synergy has required fields', () => {
    for (const synergy of synergyExplanations) {
      expect(synergy.tools).toBeDefined();
      expect(synergy.title).toBeDefined();
      expect(synergy.description).toBeDefined();
      expect(synergy.multiplier).toBeDefined();
      expect(synergy.example).toBeDefined();
    }
  });

  test('synergy tools array has at least 2 tools', () => {
    for (const synergy of synergyExplanations) {
      expect(synergy.tools.length).toBeGreaterThanOrEqual(2);
    }
  });

  test('synergy tools reference valid tool ids', () => {
    const toolIds = new Set(flywheelTools.map((t) => t.id));
    for (const synergy of synergyExplanations) {
      for (const toolId of synergy.tools) {
        expect(toolIds.has(toolId)).toBe(true);
      }
    }
  });

  test('RU synergies exist', () => {
    const ruSynergies = synergyExplanations.filter((s) => s.tools.includes('ru'));
    expect(ruSynergies.length).toBeGreaterThan(0);
  });

  test('DCG synergies exist', () => {
    const dcgSynergies = synergyExplanations.filter((s) => s.tools.includes('dcg'));
    expect(dcgSynergies.length).toBeGreaterThan(0);
  });
});

describe('flywheelDescription object', () => {
  test('has required fields', () => {
    expect(flywheelDescription.title).toBeDefined();
    expect(flywheelDescription.subtitle).toBeDefined();
    expect(flywheelDescription.description).toBeDefined();
    expect(flywheelDescription.philosophy).toBeDefined();
    expect(flywheelDescription.metrics).toBeDefined();
    expect(flywheelDescription.keyInsight).toBeDefined();
  });

  test('philosophy has entries', () => {
    expect(flywheelDescription.philosophy.length).toBeGreaterThan(0);
  });

  test('philosophy entries have title and description', () => {
    for (const item of flywheelDescription.philosophy) {
      expect(item.title).toBeDefined();
      expect(item.description).toBeDefined();
    }
  });

  test('metrics has expected keys', () => {
    expect(flywheelDescription.metrics.toolCount).toBeDefined();
    expect(flywheelDescription.metrics.languages).toBeDefined();
    expect(flywheelDescription.metrics.avgInstallTime).toBeDefined();
  });

  test('metrics toolCount matches flywheelTools length', () => {
    expect(flywheelDescription.metrics.toolCount).toBe(flywheelTools.length);
  });

  test('keyInsight mentions key tools', () => {
    expect(flywheelDescription.keyInsight).toMatch(/BV|Mail|CASS|CM|SLB|DCG|RU|NTM/);
  });
});

// ============================================================
// HELPER FUNCTION TESTS
// ============================================================

describe('getToolSynergy', () => {
  test('returns number for valid tool', () => {
    const synergy = getToolSynergy('ntm');
    expect(typeof synergy).toBe('number');
    expect(synergy).toBeGreaterThan(0);
  });

  test('returns 0 for non-existent tool', () => {
    const synergy = getToolSynergy('nonexistent');
    expect(synergy).toBe(0);
  });

  test('counts both outgoing and incoming connections', () => {
    // NTM has connections to other tools AND other tools connect to it
    const ntmSynergy = getToolSynergy('ntm');
    const ntmTool = flywheelTools.find((t) => t.id === 'ntm');

    // Should be more than just outgoing connections
    expect(ntmSynergy).toBeGreaterThanOrEqual(ntmTool?.connectsTo.length ?? 0);
  });
});

describe('getToolsBySynergy', () => {
  test('returns all tools', () => {
    const sorted = getToolsBySynergy();
    expect(sorted.length).toBe(flywheelTools.length);
  });

  test('returns tools sorted by synergy (descending)', () => {
    const sorted = getToolsBySynergy();
    for (let i = 0; i < sorted.length - 1; i++) {
      const currentSynergy = getToolSynergy(sorted[i].id);
      const nextSynergy = getToolSynergy(sorted[i + 1].id);
      expect(currentSynergy).toBeGreaterThanOrEqual(nextSynergy);
    }
  });

  test('does not modify original array', () => {
    const originalOrder = flywheelTools.map((t) => t.id);
    getToolsBySynergy();
    const afterOrder = flywheelTools.map((t) => t.id);
    expect(afterOrder).toEqual(originalOrder);
  });
});

describe('getAllConnections', () => {
  test('returns array of connections', () => {
    const connections = getAllConnections();
    expect(Array.isArray(connections)).toBe(true);
    expect(connections.length).toBeGreaterThan(0);
  });

  test('each connection has from and to', () => {
    const connections = getAllConnections();
    for (const conn of connections) {
      expect(conn.from).toBeDefined();
      expect(conn.to).toBeDefined();
    }
  });

  test('connections are unique (no duplicates)', () => {
    const connections = getAllConnections();
    const keys = connections.map((c) => [c.from, c.to].sort().join('-'));
    const uniqueKeys = new Set(keys);
    expect(uniqueKeys.size).toBe(keys.length);
  });

  test('connections reference valid tools', () => {
    const toolIds = new Set(flywheelTools.map((t) => t.id));
    const connections = getAllConnections();
    for (const conn of connections) {
      expect(toolIds.has(conn.from)).toBe(true);
      expect(toolIds.has(conn.to)).toBe(true);
    }
  });
});

describe('getPromptsByCategory', () => {
  test('returns prompts for valid category', () => {
    const exploration = getPromptsByCategory('exploration');
    expect(exploration.length).toBeGreaterThan(0);
    for (const prompt of exploration) {
      expect(prompt.category).toBe('exploration');
    }
  });

  test('returns empty array for non-matching category', () => {
    // This shouldn't match any valid category
    const result = getPromptsByCategory('nonexistent' as never);
    expect(result.length).toBe(0);
  });

  test('returns all prompts for each category', () => {
    const categories: Array<'exploration' | 'review' | 'improvement' | 'planning' | 'execution'> = [
      'exploration',
      'review',
      'improvement',
      'planning',
      'execution',
    ];

    for (const category of categories) {
      const prompts = getPromptsByCategory(category);
      const expected = agentPrompts.filter((p) => p.category === category);
      expect(prompts.length).toBe(expected.length);
    }
  });
});

describe('getScenarioById', () => {
  test('returns scenario for valid id', () => {
    const scenario = getScenarioById('daily-parallel');
    expect(scenario).toBeDefined();
    expect(scenario?.id).toBe('daily-parallel');
  });

  test('returns undefined for non-existent id', () => {
    const scenario = getScenarioById('nonexistent');
    expect(scenario).toBeUndefined();
  });

  test('returns correct scenario data', () => {
    for (const expected of workflowScenarios) {
      const actual = getScenarioById(expected.id);
      expect(actual).toEqual(expected);
    }
  });
});

// ============================================================
// INTEGRATION TESTS
// ============================================================

describe('data integrity', () => {
  test('all tool languages are represented in metrics', () => {
    const toolLanguages = new Set(flywheelTools.map((t) => t.language));
    const metricsLanguages = new Set(flywheelDescription.metrics.languages);

    for (const lang of toolLanguages) {
      expect(metricsLanguages.has(lang)).toBe(true);
    }
  });

  test('synergy explanations cover key tool combinations', () => {
    // Core loop should exist
    const coreLoop = synergyExplanations.find(
      (s) => s.tools.includes('ntm') && s.tools.includes('mail') && s.tools.includes('bv')
    );
    expect(coreLoop).toBeDefined();

    // Safety net should exist
    const safetyNet = synergyExplanations.find(
      (s) => s.tools.includes('dcg') || s.tools.includes('slb')
    );
    expect(safetyNet).toBeDefined();
  });

  test('workflow scenarios use diverse tools', () => {
    const toolsUsed = new Set<string>();
    for (const scenario of workflowScenarios) {
      for (const step of scenario.steps) {
        toolsUsed.add(step.tool);
      }
    }
    // At least 8 different tools should be used across scenarios
    expect(toolsUsed.size).toBeGreaterThanOrEqual(8);
  });
});
