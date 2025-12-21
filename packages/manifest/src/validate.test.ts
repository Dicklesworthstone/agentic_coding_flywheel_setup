/**
 * Tests for ACFS Manifest Validation
 * Related: bead mjt.3.2
 */

import { describe, test, expect } from 'bun:test';
import {
  validateDependencyExistence,
  detectDependencyCycles,
  validatePhaseOrdering,
  validateManifest,
  formatValidationErrors,
} from './validate.js';
import type { Manifest } from './types.js';

// Helper to create a minimal valid manifest
function createManifest(modules: Manifest['modules']): Manifest {
  return {
    version: 1,
    name: 'Test Manifest',
    id: 'test',
    defaults: {
      user: 'ubuntu',
      workspace_root: '/data/projects',
      mode: 'vibe',
    },
    modules,
  };
}

describe('validateDependencyExistence', () => {
  test('passes when all dependencies exist', () => {
    const manifest = createManifest([
      {
        id: 'base.system',
        description: 'Base system',
        install: ['echo "install"'],
        verify: ['echo "verify"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
      {
        id: 'shell.zsh',
        description: 'Zsh shell',
        dependencies: ['base.system'],
        install: ['echo "install"'],
        verify: ['echo "verify"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const errors = validateDependencyExistence(manifest);
    expect(errors).toHaveLength(0);
  });

  test('fails when dependency does not exist', () => {
    const manifest = createManifest([
      {
        id: 'shell.zsh',
        description: 'Zsh shell',
        dependencies: ['nonexistent.module'],
        install: ['echo "install"'],
        verify: ['echo "verify"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const errors = validateDependencyExistence(manifest);
    expect(errors).toHaveLength(1);
    expect(errors[0].code).toBe('MISSING_DEPENDENCY');
    expect(errors[0].moduleId).toBe('shell.zsh');
    expect(errors[0].context.missingDependency).toBe('nonexistent.module');
  });

  test('reports multiple missing dependencies', () => {
    const manifest = createManifest([
      {
        id: 'shell.zsh',
        description: 'Zsh shell',
        dependencies: ['missing.one', 'missing.two'],
        install: ['echo "install"'],
        verify: ['echo "verify"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const errors = validateDependencyExistence(manifest);
    expect(errors).toHaveLength(2);
  });
});

describe('detectDependencyCycles', () => {
  test('passes when no cycles exist', () => {
    const manifest = createManifest([
      {
        id: 'a',
        description: 'A',
        install: ['echo "a"'],
        verify: ['echo "a"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
      {
        id: 'b',
        description: 'B',
        dependencies: ['a'],
        install: ['echo "b"'],
        verify: ['echo "b"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
      {
        id: 'c',
        description: 'C',
        dependencies: ['b'],
        install: ['echo "c"'],
        verify: ['echo "c"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const errors = detectDependencyCycles(manifest);
    expect(errors).toHaveLength(0);
  });

  test('detects simple cycle (a -> b -> a)', () => {
    const manifest = createManifest([
      {
        id: 'a',
        description: 'A',
        dependencies: ['b'],
        install: ['echo "a"'],
        verify: ['echo "a"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
      {
        id: 'b',
        description: 'B',
        dependencies: ['a'],
        install: ['echo "b"'],
        verify: ['echo "b"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const errors = detectDependencyCycles(manifest);
    expect(errors).toHaveLength(1);
    expect(errors[0].code).toBe('DEPENDENCY_CYCLE');
    expect(errors[0].context.cyclePath).toContain('a');
    expect(errors[0].context.cyclePath).toContain('b');
  });

  test('detects self-cycle (a -> a)', () => {
    const manifest = createManifest([
      {
        id: 'a',
        description: 'A',
        dependencies: ['a'],
        install: ['echo "a"'],
        verify: ['echo "a"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const errors = detectDependencyCycles(manifest);
    expect(errors).toHaveLength(1);
    expect(errors[0].code).toBe('DEPENDENCY_CYCLE');
  });

  test('detects longer cycle (a -> b -> c -> a)', () => {
    const manifest = createManifest([
      {
        id: 'a',
        description: 'A',
        dependencies: ['c'],
        install: ['echo "a"'],
        verify: ['echo "a"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
      {
        id: 'b',
        description: 'B',
        dependencies: ['a'],
        install: ['echo "b"'],
        verify: ['echo "b"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
      {
        id: 'c',
        description: 'C',
        dependencies: ['b'],
        install: ['echo "c"'],
        verify: ['echo "c"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const errors = detectDependencyCycles(manifest);
    expect(errors).toHaveLength(1);
    expect(errors[0].code).toBe('DEPENDENCY_CYCLE');
    expect(errors[0].context.cycleLength).toBe(3);
  });
});

describe('validatePhaseOrdering', () => {
  test('passes when deps are in earlier phase', () => {
    const manifest = createManifest([
      {
        id: 'base',
        description: 'Base',
        phase: 1,
        install: ['echo "base"'],
        verify: ['echo "base"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
      {
        id: 'shell',
        description: 'Shell',
        phase: 2,
        dependencies: ['base'],
        install: ['echo "shell"'],
        verify: ['echo "shell"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const errors = validatePhaseOrdering(manifest);
    expect(errors).toHaveLength(0);
  });

  test('passes when deps are in same phase', () => {
    const manifest = createManifest([
      {
        id: 'a',
        description: 'A',
        phase: 2,
        install: ['echo "a"'],
        verify: ['echo "a"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
      {
        id: 'b',
        description: 'B',
        phase: 2,
        dependencies: ['a'],
        install: ['echo "b"'],
        verify: ['echo "b"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const errors = validatePhaseOrdering(manifest);
    expect(errors).toHaveLength(0);
  });

  test('fails when dep is in later phase', () => {
    const manifest = createManifest([
      {
        id: 'early',
        description: 'Early module',
        phase: 1,
        dependencies: ['late'],
        install: ['echo "early"'],
        verify: ['echo "early"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
      {
        id: 'late',
        description: 'Late module',
        phase: 5,
        install: ['echo "late"'],
        verify: ['echo "late"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const errors = validatePhaseOrdering(manifest);
    expect(errors).toHaveLength(1);
    expect(errors[0].code).toBe('PHASE_VIOLATION');
    expect(errors[0].context.modulePhase).toBe(1);
    expect(errors[0].context.dependencyPhase).toBe(5);
  });

  test('uses default phase 1 when not specified', () => {
    const manifest = createManifest([
      {
        id: 'explicit',
        description: 'Explicit phase 1',
        phase: 1,
        dependencies: ['implicit'],
        install: ['echo "explicit"'],
        verify: ['echo "explicit"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
      {
        id: 'implicit',
        description: 'Implicit phase 1',
        // No phase specified, should default to 1
        install: ['echo "implicit"'],
        verify: ['echo "implicit"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const errors = validatePhaseOrdering(manifest);
    expect(errors).toHaveLength(0);
  });
});

describe('validateManifest (combined)', () => {
  test('passes with valid manifest', () => {
    const manifest = createManifest([
      {
        id: 'base',
        description: 'Base',
        phase: 1,
        install: ['echo "base"'],
        verify: ['echo "base"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
      {
        id: 'shell',
        description: 'Shell',
        phase: 2,
        dependencies: ['base'],
        install: ['echo "shell"'],
        verify: ['echo "shell"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const result = validateManifest(manifest);
    expect(result.valid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  test('stops at first error category', () => {
    // Manifest with both missing dependency and cycle
    // Should only report missing dependency (first check)
    const manifest = createManifest([
      {
        id: 'a',
        description: 'A',
        dependencies: ['nonexistent', 'b'],
        install: ['echo "a"'],
        verify: ['echo "a"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
      {
        id: 'b',
        description: 'B',
        dependencies: ['a'],
        install: ['echo "b"'],
        verify: ['echo "b"'],
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
      },
    ]);

    const result = validateManifest(manifest);
    expect(result.valid).toBe(false);
    // Should only see MISSING_DEPENDENCY, not DEPENDENCY_CYCLE
    expect(result.errors.every((e) => e.code === 'MISSING_DEPENDENCY')).toBe(true);
  });
});

describe('formatValidationErrors', () => {
  test('formats passing result', () => {
    const result = { valid: true, errors: [] };
    const formatted = formatValidationErrors(result);
    expect(formatted).toContain('✓');
    expect(formatted).toContain('passed');
  });

  test('formats failing result with hints', () => {
    const result = {
      valid: false,
      errors: [
        {
          code: 'MISSING_DEPENDENCY' as const,
          message: 'Module "a" depends on "b" which does not exist',
          moduleId: 'a',
          context: { missingDependency: 'b' },
        },
      ],
    };
    const formatted = formatValidationErrors(result);
    expect(formatted).toContain('✗');
    expect(formatted).toContain('MISSING_DEPENDENCY');
    expect(formatted).toContain('Check spelling');
    expect(formatted).toContain('1 error');
  });
});
