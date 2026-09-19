#!/usr/bin/env python3
"""Actual main()/loader orchestration with host-changing callees replaced.

Defaults to this checkout's complete install.sh. Explicit partial-checkout
ACFS_INSTALLER_MAIN_TEST_SOURCE and ACFS_INSTALLER_LOADER_TEST_SOURCE overrides
must be reported as snapshot tests, never whole-installer execution. No package
manager, reboot, or live release discovery is invoked. Temporary lock files are
real; their directories and all evidence are retained.
"""
from __future__ import annotations
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MAIN = Path(os.environ.get('ACFS_INSTALLER_MAIN_TEST_SOURCE', ROOT / 'install.sh'))
LOADER = Path(os.environ.get('ACFS_INSTALLER_LOADER_TEST_SOURCE', ROOT / 'install.sh'))
PHASE = Path(os.environ.get('ACFS_INSTALLER_TEST_SOURCE', ROOT / 'install.sh'))
POLICY = Path(os.environ.get('ACFS_UPGRADE_POLICY_TEST_SOURCE', ROOT / 'scripts/lib/ubuntu_upgrade.sh'))


def definition(text, name):
    found = re.search(r'^' + re.escape(name) + r'\(\) \{\n.*?^\}', text, re.M | re.S)
    if not found:
        raise ValueError('Missing actual installer function: ' + name)
    return found[0]


def definitions(text, required, optional=()):
    return '\n'.join(definition(text, name) for name in required) + '\n' + '\n'.join(
        definition(text, name) for name in optional if re.search(r'^' + name + r'\(\)', text, re.M))


class MainUpgradeOrderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = definitions(MAIN.read_text(), ['main'], [
            'acfs_validate_ubuntu_target', 'acfs_ubuntu_upgrade_requested',
            'acfs_guard_ubuntu_install_checkpoint'])

    def run_main(self, *, overrides=None, arguments=(), extra='', uid=None):
        root = Path(tempfile.mkdtemp(prefix='acfs-main-order-'))
        root.chmod(0o755)
        home = root / 'home'
        home.mkdir(mode=0o700)
        if uid is not None:
            os.chown(home, uid, uid)
        prelude = r'''
set -euo pipefail
exec 3>&1
trace() { printf 'EVENT:%s\n' "$*" >&3; }
log_error() { printf 'ERROR:%s\n' "$*" >&2; }
log_fatal() { log_error "$@"; exit 1; }
log_info() { :; }; log_debug() { :; }; log_detail() { :; }; log_warn() { :; }
source() {
    if [[ "$1" == /etc/os-release ]]; then
        [[ "$TEST_OS_STATUS" == 0 ]] || return "$TEST_OS_STATUS"
        ID="$TEST_OS"; VERSION_ID=24.04; return 0
    fi
    builtin source "$@"
}
parse_args() { trace parse; }
acfs_require_ref_arg_value() { :; }
normalize_read_only_modes() { :; }
acfs_normalize_verified_installer_cache_configuration() { :; }
fetch_commit_sha() { trace ref; ACFS_COMMIT_SHA_FULL=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; }
print_pinned_ref() { trace pin; }
bootstrap_repo_archive() { trace archive; ACFS_BOOTSTRAP_DIR="$TEST_ROOT/archive"; }
acfs_run_verified_bootstrap_installer() { trace verified_child; return "$TEST_CHILD_STATUS"; }
detect_environment() { trace environment; }
acfs_read_upgrade_checkpoint() {
    trace "checkpoint:$1:$2"
    [[ "$TEST_CHECKPOINT_STATUS" == 0 ]] || return "$TEST_CHECKPOINT_STATUS"
    printf '%s\n' "$TEST_STAGE"
}
acfs_remember_install_lock() { trace install_lock; }
source_generated_installers() { trace generated; }
acfs_apply_legacy_skips() { :; }
acfs_apply_profile() { trace profile; return "$TEST_SELECTION_STATUS"; }
acfs_resolve_selection() { trace selection; return "$TEST_SELECTION_STATUS"; }
acfs_interactive_module_selector() { trace interactive; return "$TEST_SELECTION_STATUS"; }
list_modules() { trace list; }
print_execution_plan() { trace plan; }
print_summary() { trace summary; }
state_backup_and_remove() { trace mut:reset; }
ensure_root() { trace root; if [[ "$TEST_ROOT_STATUS" != 0 ]]; then exit "$TEST_ROOT_STATUS"; fi; }
validate_target_user() { trace user; if [[ "$TEST_USER_STATUS" != 0 ]]; then exit "$TEST_USER_STATUS"; fi; }
init_target_paths() { trace paths; }
ensure_ubuntu() { trace supported_os; }
run_ubuntu_upgrade_phase() {
    trace upgrade
    for argument in "$@"; do trace "upgrade_arg:$argument"; done
    if [[ "$TEST_UPGRADE_EXITS" == true ]]; then trace reboot_requested; exit "$TEST_UPGRADE_STATUS"; fi
    return "$TEST_UPGRADE_STATUS"
}
install_gum_early() {
    if [[ "$DRY_RUN" != true && "$PRINT_MODE" != true ]]; then trace mut:gum; fi
}
print_banner() { trace banner; }
run_autofix_checks() {
    if [[ "$DRY_RUN" != true && "$PRINT_MODE" != true ]]; then trace mut:autofix; fi
}
run_preflight_checks() { trace preflight; return 0; }
acfs_early_sudo_binary_path() { trace unexpected_sudo; return 1; }
acfs_early_system_binary_path() {
    case "$1" in
        curl|jq|git) [[ "$TEST_MISSING_TOOLS" != true ]] || return 1; printf '/usr/bin/%s\n' "$1" ;;
        apt-get) printf 'fixture_apt\n' ;;
        pacman) printf 'fixture_pacman\n' ;;
        *) return 1 ;;
    esac
}
fixture_apt() { trace "mut:apt:$*"; }
fixture_pacman() { trace "mut:pacman:$*"; }
disable_needrestart_apt_hook() { trace mut:needrestart; }
acfs_log_init() { trace logs; }
ensure_base_deps() { trace mut:base; }
state_ensure_valid() { trace normal_state; }
confirm_resume() { trace normal_install_ready; exit 0; }
'''
        settings = dict(
            TEST_ROOT=str(root), TARGET_HOME=str(home), ACFS_HOME=str(home / '.acfs'),
            TARGET_USER='ubuntu', SCRIPT_DIR=str(root), BOOTSTRAP_ARCHIVE_PATH='',
            YES_MODE='true', DRY_RUN='false', PRINT_MODE='false', PRINT_PLAN_MODE='false',
            LIST_MODULES='false', PIN_REF_MODE='false', RESET_STATE_ONLY='false',
            SKIP_PREFLIGHT='false', SKIP_UBUNTU_UPGRADE='false', ACFS_CLI_PROFILE='',
            ACFS_EXPLICIT_TARGETED_SELECTION='false', TARGET_UBUNTU_VERSION='26.04',
            TARGET_UBUNTU_VERSION_EXPLICIT='false', ACFS_REF='main',
            ACFS_CHECKSUMS_REF='main', ACFS_DISTRO_FAMILY='debian',
            ACFS_REPO_OWNER='fixture', ACFS_REPO_NAME='fixture', YELLOW='', NC='',
            TEST_OS='ubuntu', TEST_OS_STATUS='0', TEST_STAGE='not_started',
            TEST_CHECKPOINT_STATUS='0', TEST_UPGRADE_STATUS='0', TEST_UPGRADE_EXITS='false',
            TEST_SELECTION_STATUS='0', TEST_ROOT_STATUS='0', TEST_USER_STATUS='0',
            TEST_MISSING_TOOLS='true', TEST_CHILD_STATUS='0')
        settings.update(overrides or {})
        if settings['RESET_STATE_ONLY'] == 'true':
            (home / '.acfs').mkdir(mode=0o700)
            (home / '.acfs/state.json').write_text('{"evidence":"keep"}')
        assignments = '\n'.join(f'{key}={shlex.quote(value)}' for key, value in settings.items())
        invocation = 'main ' + ' '.join(map(shlex.quote, arguments))
        script = '\n'.join([prelude, assignments, self.source, extra, invocation])
        (root / 'test-script.sh').write_text(script)
        result = subprocess.run(['/bin/bash', '-p', '-c', script], text=True, capture_output=True,
                                timeout=10, user=uid, group=uid,
                                env={'PATH': '/usr/bin:/bin', 'HOME': str(home)})
        events = [line[6:] for line in result.stdout.splitlines() if line.startswith('EVENT:')]
        return result, events, root

    def assert_no_mutation(self, result, events):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any(e.startswith('mut:') for e in events), events)
        self.assertNotIn('normal_install_ready', events)

    def test_upgrade_precedes_all_package_helpers(self):
        result, events, _ = self.run_main()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(events.count('upgrade'), 1, events)
        for event in events:
            if event.startswith('mut:'):
                self.assertLess(events.index('upgrade'), events.index(event), events)
        self.assertIn('normal_install_ready', events)

    def test_failed_upgrade_never_reaches_package_helpers(self):
        for code in ('1', '2', '17'):
            with self.subTest(code=code):
                result, events, _ = self.run_main(overrides={'TEST_UPGRADE_STATUS': code})
                self.assert_no_mutation(result, events)

    def test_scheduled_reboot_stops_before_normal_bootstrap(self):
        result, events, _ = self.run_main(overrides={'TEST_UPGRADE_EXITS': 'true'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('reboot_requested', events)
        self.assertFalse(any(e.startswith('mut:') for e in events), events)

    def test_all_active_and_failed_stages_block_every_mutating_mode(self):
        for stage in ('initializing', 'upgrading', 'awaiting_reboot', 'resumed', 'step_complete', 'error'):
            for mode in ({}, {'SKIP_UBUNTU_UPGRADE': 'true'},
                         {'ACFS_EXPLICIT_TARGETED_SELECTION': 'true'}, {'RESET_STATE_ONLY': 'true'}):
                with self.subTest(stage=stage, mode=mode):
                    result, events, root = self.run_main(overrides={'TEST_STAGE': stage, **mode})
                    self.assert_no_mutation(result, events)
                    self.assertNotIn('install_lock', events)
                    if mode.get('RESET_STATE_ONLY') == 'true':
                        self.assertEqual((root / 'home/.acfs/state.json').read_text(), '{"evidence":"keep"}')

    def test_unreadable_and_unknown_checkpoints_block_mutations(self):
        for changes in ({'TEST_CHECKPOINT_STATUS': '1'}, {'TEST_STAGE': 'unknown'}, {'TEST_STAGE': ''}):
            result, events, _ = self.run_main(overrides=changes)
            self.assert_no_mutation(result, events)

    def test_pre_upgrade_checkpoint_requires_the_actual_resume_path(self):
        for mode in ({'SKIP_UBUNTU_UPGRADE': 'true'}, {'ACFS_EXPLICIT_TARGETED_SELECTION': 'true'},
                     {'RESET_STATE_ONLY': 'true'}):
            result, events, _ = self.run_main(overrides={'TEST_STAGE': 'pre_upgrade_reboot', **mode})
            self.assert_no_mutation(result, events)
        result, events, _ = self.run_main(overrides={'TEST_STAGE': 'pre_upgrade_reboot'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(events.count('upgrade'), 1)

    def test_explicit_target_is_honored_for_narrow_module_and_phase_requests(self):
        for flag, value in (('--only', 'agents.claude'), ('--only-phase', '6')):
            args = (flag, value, '--target-ubuntu=26.04', '--mode', 'safe', '--skip', 'cloud.vercel')
            result, events, _ = self.run_main(overrides={
                'ACFS_EXPLICIT_TARGETED_SELECTION': 'true', 'TARGET_UBUNTU_VERSION_EXPLICIT': 'true'}, arguments=args)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(events.count('upgrade'), 1)
            self.assertEqual([e[12:] for e in events if e.startswith('upgrade_arg:')], list(args))

    def test_implicit_narrow_repair_skips_upgrade_but_not_checkpoint_gate(self):
        result, events, _ = self.run_main(overrides={'ACFS_EXPLICIT_TARGETED_SELECTION': 'true'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('upgrade', events)
        self.assertIn('checkpoint:/var/lib/acfs/state.json:26.04', events)
        self.assertIn('normal_install_ready', events)

    def test_skip_wins_over_explicit_target_but_not_checkpoint_gate(self):
        result, events, _ = self.run_main(overrides={'SKIP_UBUNTU_UPGRADE': 'true', 'TARGET_UBUNTU_VERSION_EXPLICIT': 'true'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('upgrade', events)
        self.assertIn('checkpoint:/var/lib/acfs/state.json:26.04', events)

    def test_readonly_modes_do_not_require_healthy_checkpoint_or_start_upgrade(self):
        for flag in ('LIST_MODULES', 'PRINT_PLAN_MODE', 'DRY_RUN', 'PRINT_MODE'):
            with self.subTest(flag=flag):
                result, events, _ = self.run_main(overrides={flag: 'true', 'TEST_CHECKPOINT_STATUS': '1'})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('upgrade', events)
                self.assertFalse(any(e.startswith(('mut:', 'checkpoint:')) for e in events), events)

    def test_invalid_targets_stop_before_network_or_environment_loading(self):
        for target in ('25.10', '', '24.04.1', '26.10', '$(touch never)', '26.04\n', '026.04'):
            with self.subTest(target=target):
                result, events, _ = self.run_main(overrides={'TARGET_UBUNTU_VERSION': target, 'SCRIPT_DIR': ''})
                self.assert_no_mutation(result, events)
                self.assertEqual(events, ['parse'])

    def test_system_checkpoint_path_cannot_be_redirected_by_environment(self):
        result, events, _ = self.run_main(overrides={'ACFS_RESUME_DIR': '/untrusted', 'ACFS_STATE_FILE': '/untrusted/state', 'TEST_STAGE': 'upgrading'})
        self.assert_no_mutation(result, events)
        self.assertIn('checkpoint:/var/lib/acfs/state.json:26.04', events)

    def test_nonubuntu_does_not_interpret_ubuntu_checkpoints(self):
        result, events, _ = self.run_main(overrides={'TEST_OS': 'arch', 'ACFS_DISTRO_FAMILY': 'arch', 'TEST_CHECKPOINT_STATUS': '1'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(e.startswith('checkpoint:') for e in events))
        self.assertTrue(any(e.startswith('mut:pacman:') for e in events))

    def test_unreadable_or_empty_os_identity_blocks_before_mutations(self):
        for setting in ({'TEST_OS_STATUS': '1'}, {'TEST_OS': ''}):
            result, events, _ = self.run_main(overrides=setting)
            self.assert_no_mutation(result, events)

    def test_bad_module_selection_never_starts_an_upgrade(self):
        result, events, _ = self.run_main(overrides={'TEST_SELECTION_STATUS': '1'})
        self.assert_no_mutation(result, events)
        self.assertNotIn('upgrade', events)

    def test_root_and_user_validation_failures_do_not_run_gum_or_autofix(self):
        for flag in ('TEST_ROOT_STATUS', 'TEST_USER_STATUS'):
            result, events, _ = self.run_main(overrides={flag: '1'})
            self.assert_no_mutation(result, events)
            self.assertNotIn('upgrade', events)

    def test_streamed_parent_still_delegates_only_to_verified_child(self):
        for code in ('0', '17'):
            result, events, _ = self.run_main(overrides={'SCRIPT_DIR': '', 'TEST_CHILD_STATUS': code})
            self.assertEqual(result.returncode, int(code), result.stderr)
            self.assertEqual(events, ['parse', 'ref', 'archive', 'verified_child'])

    def test_completed_checkpoint_allows_normal_upgrade_decision(self):
        result, events, _ = self.run_main(overrides={'TEST_STAGE': 'completed'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(events.count('upgrade'), 1)

    def test_profile_selection_does_not_become_an_implicit_targeted_repair(self):
        result, events, _ = self.run_main(overrides={'ACFS_CLI_PROFILE': 'minimal'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('profile', events)
        self.assertIn('upgrade', events)

    def test_preflight_skip_does_not_skip_upgrade_or_checkpoint_checks(self):
        result, events, _ = self.run_main(overrides={'SKIP_PREFLIGHT': 'true'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('upgrade', events)
        self.assertIn('checkpoint:/var/lib/acfs/state.json:26.04', events)
        self.assertNotIn('preflight', events)


class IntegratedUpgradeFlowTests(unittest.TestCase):
    """Connect actual main, phase, loader, graph and jq state reads.

    The shell runs only in isolated temporary directories. OS identity,
    package acquisition, upgrade lock, preflight and release execution remain
    explicit test doubles; no live OS upgrade or whole-installer run is claimed.
    """
    run_main = MainUpgradeOrderTests.run_main
    assert_no_mutation = MainUpgradeOrderTests.assert_no_mutation

    @classmethod
    def setUpClass(cls):
        cls.source = definitions(MAIN.read_text(), ['main'], [
            'acfs_validate_ubuntu_target', 'acfs_ubuntu_upgrade_requested',
            'acfs_guard_ubuntu_install_checkpoint'])
        source = PHASE.read_text()
        cls.phase = definitions(source, ['run_ubuntu_upgrade_phase',
            'release_ubuntu_upgrade_lock_if_acquired', 'restore_previous_acfs_state_file'])
        reader = definition(source, 'acfs_read_upgrade_checkpoint')
        cls.reader = reader.replace('acfs_read_upgrade_checkpoint()', '_fixture_read_checkpoint()', 1)
        cls.loader = definition(LOADER.read_text(), '_source_ubuntu_upgrade_lib')
        cls.policy = definitions(POLICY.read_text(), ['ubuntu_get_version_number', 'ubuntu_version_gte',
            'ubuntu_validate_upgrade_versions', 'ubuntu_get_next_version_hardcoded',
            'ubuntu_calculate_upgrade_path'])

    def integrated(self, *, version='24.04', state=None, options=None, extra='', arguments=()):
        setup = r'''
mkdir -p "$TEST_ROOT/recovery" "$TEST_ROOT/policy/scripts/lib"
chmod 700 "$TEST_ROOT/recovery"
ACFS_RESUME_DIR="$TEST_ROOT/recovery"
ACFS_LIB_DIR="$TEST_ROOT/policy/scripts/lib"
ACFS_TRUSTED_INTERNAL_SOURCE_ROOT="$TEST_ROOT/policy"
source() {
    if [[ "$1" == /etc/os-release ]]; then
        ID="$TEST_OS"; VERSION_ID="$TEST_VERSION"; return 0
    fi
    builtin source "$@"
}
acfs_read_upgrade_checkpoint() {
    trace "real_checkpoint:$1:$2"
    case "$1" in
        /var/lib/acfs/state.json|"$ACFS_RESUME_DIR/state.json") ;;
        *) trace unexpected_state_path; return 1 ;;
    esac
    _fixture_read_checkpoint "$ACFS_RESUME_DIR/state.json" "$2"
}
acfs_early_system_binary_path() {
    case "$1" in
        jq|curl|git|stat|mkdir) printf '/usr/bin/%s\n' "$1" ;;
        apt-get) echo fixture_apt ;;
        *) return 1 ;;
    esac
}
ubuntu_get_version_string() { printf '%s\n' "$TEST_VERSION"; }
upgrade_acquire_lock() { trace upgrade_lock; return 0; }
upgrade_release_lock() { trace upgrade_unlock; }
ubuntu_prepare_eol_repositories() { trace eol_prepare; }
ubuntu_preflight_checks() { trace upgrade_preflight; return 0; }
state_update() { trace checkpoint_update; }
state_ensure_valid() { trace state_validate; }
state_load() { [[ -f "$ACFS_STATE_FILE" ]] && cat "$ACFS_STATE_FILE"; }
state_init() { trace state_init; printf '{"schema_version":3}\n' > "$ACFS_STATE_FILE"; }
ubuntu_start_upgrade_sequence() {
    trace "release_target:$UBUNTU_TARGET_VERSION:$UBUNTU_TARGET_VERSION_NUM"
    trace "release_hops:$(ubuntu_calculate_upgrade_path | tr '\n' ',')"
    for arg in "$@"; do trace "release_arg:$arg"; done
    return 0
}
'''
        # Store the real graph definitions in a file read by the actual loader.
        setup += '\ncat > "$ACFS_LIB_DIR/ubuntu_upgrade.sh" <<\'FIXTURE_POLICY\'\n' + self.policy + '\nFIXTURE_POLICY\n'
        if state is not None:
            setup += '\nprintf %s ' + shlex.quote(state) + ' > "$ACFS_RESUME_DIR/state.json"\n'
            setup += 'chmod 600 "$ACFS_RESUME_DIR/state.json"\n'
        return self.run_main(overrides={'TEST_VERSION': version, 'TEST_MISSING_TOOLS': 'false', **(options or {})},
            extra='\n'.join([self.reader, self.phase, self.loader, setup, extra]), arguments=arguments)

    def test_old_lts_exits_for_upgrade_before_normal_installs(self):
        for version, hops in (('22.04', '24.04,26.04,'), ('24.04', '26.04,'), ('25.10', '26.04,')):
            with self.subTest(version=version):
                result, events, _ = self.integrated(version=version)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('release_target:26.04:2604', events)
                self.assertIn('release_hops:' + hops, events)
                self.assertFalse(any(e.startswith('mut:') for e in events), events)
                self.assertNotIn('normal_install_ready', events)

    def test_supported_destination_continues_normal_install_without_distribution_changes(self):
        for version, target in (('26.04','26.04'), ('24.04','24.04'), ('26.04','24.04')):
            result, events, _ = self.integrated(version=version, options={'TARGET_UBUNTU_VERSION': target})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('normal_install_ready', events)
            self.assertNotIn('upgrade_lock', events)
            self.assertFalse(any(e.startswith('release_target:') for e in events))

    def test_explicit_narrow_upgrade_keeps_exact_resume_arguments(self):
        args = ('--only', 'lang.bun', '--skip', 'cloud.vercel', '--mode', 'safe', '--ref',
                'a' * 40, '--target-ubuntu=26.04', '--verified-installer-cache', '/cache path')
        result, events, _ = self.integrated(options={'ACFS_EXPLICIT_TARGETED_SELECTION': 'true',
            'TARGET_UBUNTU_VERSION_EXPLICIT': 'true'}, arguments=args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('release_target:26.04:2604', events)
        self.assertEqual([e[12:] for e in events if e.startswith('release_arg:')][1:], list(args))
        self.assertFalse(any(e.startswith('mut:') for e in events))

    def test_readable_real_active_checkpoint_blocks_skip_and_narrow_repairs(self):
        state = '{"schema_version":3,"ubuntu_upgrade":{"enabled":true,"current_stage":"upgrading","target_version":"26.04"}}'
        for options in ({}, {'SKIP_UBUNTU_UPGRADE':'true'}, {'ACFS_EXPLICIT_TARGETED_SELECTION':'true'}):
            result, events, root = self.integrated(state=state, options=options)
            self.assert_no_mutation(result, events)
            self.assertEqual((root / 'recovery/state.json').read_text(), state)
            self.assertNotIn('install_lock', events)

    def test_malformed_real_checkpoint_blocks_before_any_state_repair(self):
        for state in ('{broken', '{}', 'null', '{"schema_version":999}'):
            result, events, root = self.integrated(state=state)
            self.assert_no_mutation(result, events)
            self.assertEqual((root / 'recovery/state.json').read_text(), state)
            self.assertNotIn('state_validate', events)

    def test_local_archive_cannot_begin_upgrade_or_normal_package_install(self):
        result, events, _ = self.integrated(options={'ACFS_LOCAL_ARCHIVE_SOURCE':'true'})
        self.assert_no_mutation(result, events)
        self.assertNotIn('upgrade_lock', events)

    def test_recovery_state_changed_after_main_guard_is_not_bypassed(self):
        extra = r'''upgrade_acquire_lock() {
    trace upgrade_lock
    printf '%s' '{"schema_version":3,"ubuntu_upgrade":{"enabled":true,"current_stage":"upgrading","target_version":"26.04"}}' > "$ACFS_STATE_FILE"
}'''
        result, events, root = self.integrated(extra=extra)
        self.assert_no_mutation(result, events)
        self.assertIn('upgrade_unlock', events)
        self.assertIn('upgrading', (root / 'recovery/state.json').read_text())

    def test_actual_library_source_failure_cannot_be_masked_by_loader_or_main(self):
        result, events, _ = self.integrated(extra='printf "return 17\\n" > "$ACFS_LIB_DIR/ubuntu_upgrade.sh"')
        self.assert_no_mutation(result, events)
        self.assertNotIn('upgrade_lock', events)

    def test_release_executor_failure_stops_main_and_preserves_checkpoint(self):
        state = '{"schema_version":3,"ubuntu_upgrade":{"enabled":false,"current_stage":"not_started"}}'
        result, events, root = self.integrated(state=state,
            extra='ubuntu_start_upgrade_sequence() { trace release_failed; return 17; }')
        self.assert_no_mutation(result, events)
        self.assertIn('upgrade_unlock', events)
        self.assertEqual((root / 'recovery/state.json').read_text(), state)

    def test_nonubuntu_path_does_not_apply_ubuntu_release_policy(self):
        result, events, _ = self.integrated(options={'TEST_OS':'arch', 'ACFS_DISTRO_FAMILY':'arch'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('normal_install_ready', events)
        self.assertFalse(any(e.startswith(('real_checkpoint:', 'release_target:')) for e in events))


class PolicyLoadingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.function = definition(LOADER.read_text(), '_source_ubuntu_upgrade_lib')

    def load(self, body='printf "POLICY_LOADED\\n"\nreturn 0\n', *, marker='', mismatch=False, symlink=False, conditional=True):
        root = Path(tempfile.mkdtemp(prefix='acfs-policy-load-'))
        lib = root / 'scripts/lib'
        lib.mkdir(parents=True)
        target = lib / 'ubuntu_upgrade.sh'
        if symlink:
            external = root / 'redirected.sh'
            external.write_text(body)
            target.symlink_to(external)
        else:
            target.write_text(body)
        script = '\n'.join([
            'set -euo pipefail', 'log_error() { printf "%s\\n" "$*" >&2; }',
            'ACFS_LIB_DIR=' + shlex.quote(str(lib)),
            'ACFS_TRUSTED_INTERNAL_SOURCE_ROOT=' + shlex.quote(str(root) if not mismatch else '/different'),
            'export ACFS_UBUNTU_UPGRADE_LOADED=' + shlex.quote(marker), self.function,
            'if _source_ubuntu_upgrade_lib; then echo ACCEPTED; else echo REFUSED; exit 1; fi'
            if conditional else '_source_ubuntu_upgrade_lib; echo ACCEPTED'])
        return subprocess.run(['/bin/bash', '-p', '-c', script], capture_output=True, text=True, timeout=5)

    def test_loads_successful_verified_policy(self):
        result = self.load()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('POLICY_LOADED', result.stdout)

    def test_source_failure_is_not_converted_to_success_in_a_conditional(self):
        for code in (1, 2, 17):
            result = self.load(f'return {code}\n')
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('ACCEPTED', result.stdout)

    def test_syntax_error_is_refused(self):
        result = self.load('broken() {\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('ACCEPTED', result.stdout)

    def test_inherited_markers_neither_skip_loading_nor_hide_failure(self):
        for marker in ('1', 'true', 'forged'):
            result = self.load(marker=marker)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('POLICY_LOADED', result.stdout)
            self.assertNotEqual(self.load('return 1\n', marker=marker).returncode, 0)

    def test_verified_root_mismatch_cannot_be_overridden_by_marker(self):
        result = self.load(marker='1', mismatch=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('POLICY_LOADED', result.stdout)

    def test_symlinked_policy_is_not_sourced(self):
        result = self.load(symlink=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('POLICY_LOADED', result.stdout)

    def test_nonconditional_source_failure_also_stops(self):
        self.assertNotEqual(self.load('return 1\n', conditional=False).returncode, 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
