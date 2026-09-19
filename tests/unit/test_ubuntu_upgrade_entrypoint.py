#!/usr/bin/env python3
"""Exercise the actual installer phase and policy functions without OS mutation.

By default read install.sh and ubuntu_upgrade.sh in this checkout. For an
explicitly identified partial-checkout run, ACFS_INSTALLER_TEST_SOURCE and
ACFS_UPGRADE_POLICY_TEST_SOURCE can point at fetched function snapshots.
This harness does not source/execute the whole installer. The OS identity,
release executor, package manager, state lifecycle and lock are test doubles;
Bash control flow and the release graph under test are production source.
"""
from __future__ import annotations
import os
import json
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest
from contextlib import contextmanager

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get('ACFS_INSTALLER_TEST_SOURCE', ROOT / 'install.sh'))
POLICY = Path(os.environ.get('ACFS_UPGRADE_POLICY_TEST_SOURCE', ROOT / 'scripts/lib/ubuntu_upgrade.sh'))


@contextmanager
def fixture_directory():
    # Retain fixture evidence; this suite never deletes directories or files.
    yield tempfile.mkdtemp(prefix='acfs-upgrade-test-')


def definition(source: str, name: str) -> str:
    match = re.search(r'^' + re.escape(name) + r'\(\) \{\n.*?^\}', source, re.M | re.S)
    if not match:
        raise ValueError(f'Missing production function: {name}')
    return match[0]


class UpgradeEntrypointTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.geteuid() != 0:
            raise RuntimeError('Run this root-orchestration suite in a disposable Linux container as root; it substitutes all package/upgrade execution')
        if Path('/var/run/reboot-required').exists():
            raise RuntimeError('Run in a disposable environment without a pending host reboot')
        source, policy = SOURCE.read_text(), POLICY.read_text()
        cls.source = source
        cls.functions = '\n'.join(definition(source, name) for name in (
            'run_ubuntu_upgrade_phase', 'release_ubuntu_upgrade_lock_if_acquired',
            'restore_previous_acfs_state_file'))
        # A new state-reader helper, when present, runs real jq against fixture files.
        if re.search(r'^acfs_read_upgrade_checkpoint\(\)', source, re.M):
            cls.functions += '\n' + definition(source, 'acfs_read_upgrade_checkpoint')
        cls.policy = '\n'.join(definition(policy, name) for name in (
            'ubuntu_get_version_number', 'ubuntu_version_gte', 'ubuntu_validate_upgrade_versions',
            'ubuntu_get_next_version_hardcoded', 'ubuntu_calculate_upgrade_path'))
        cls.default = re.search(r'^TARGET_UBUNTU_VERSION="([^"]+)"$', source, re.M)[1]

    def invoke(self, *, version='24.04', target='26.04', stage='not_started',
               explicit=True, overrides='', conditional=True, state=None, args=(), uid=None,
               state_kind=None, reboot_required=False):
        with fixture_directory() as directory:
            path = Path(directory)
            # Reads only for the non-root cases; no privilege-changing host commands.
            path.chmod(0o755)
            if reboot_required:
                (path / 'reboot-required').write_text('fixture pending reboot\n')
            if state is None and stage != 'not_started':
                state = self.checkpoint(stage, target)
            if state is not None:
                (path / 'state.json').write_text(state)
                (path / 'state.json').chmod(0o644)
            if state_kind == 'symlink':
                (path / 'evidence.json').write_text(self.checkpoint('upgrading', target))
                (path / 'state.json').symlink_to(path / 'evidence.json')
            elif state_kind == 'hardlink':
                os.link(path / 'state.json', path / 'evidence.json')
            elif state_kind == 'writable':
                (path / 'state.json').chmod(0o666)
            elif state_kind == 'fifo':
                os.mkfifo(path / 'state.json')
            elif state_kind == 'directory':
                (path / 'state.json').mkdir()
            elif state_kind == 'oversized':
                with (path / 'state.json').open('wb') as stream:
                    stream.truncate(1048577)
            elif state_kind == 'nonroot':
                os.chown(path / 'state.json', 65534, 65534)
            prelude = r'''
set -euo pipefail
exec 3>&1
trace() { printf 'EVENT:%s\n' "$*" >&3; }
log_detail() { :; }
log_warn() { printf 'WARN:%s\n' "$*" >&2; }
log_error() { printf 'ERROR:%s\n' "$*" >&2; }
log_info() { :; }
log_success() { :; }
log_step() { :; }
source() {
    if [[ "$1" == /etc/os-release ]]; then
        ID="${TEST_OS_ID:-ubuntu}"; VERSION_ID="$TEST_VERSION"; return 0
    fi
    builtin source "$@"
}
ubuntu_get_version_string() { printf '%s\n' "$TEST_VERSION"; }
_source_ubuntu_upgrade_lib() {
    trace "library:${UBUNTU_TARGET_VERSION:-unset}:${UBUNTU_TARGET_VERSION_NUM:-unset}"
    UBUNTU_TARGET_VERSION="${UBUNTU_TARGET_VERSION:-26.04}"
    case "$UBUNTU_TARGET_VERSION" in 22.04|24.04|26.04) ;; *) return 1 ;; esac
    UBUNTU_TARGET_VERSION_NUM="${UBUNTU_TARGET_VERSION/./}"
}
acfs_early_system_binary_path() {
    case "$1" in
        jq) printf '/usr/bin/jq\n' ;;
        curl) printf '/usr/bin/curl\n' ;;
        mkdir) printf '/usr/bin/mkdir\n' ;;
        stat) printf '/usr/bin/stat\n' ;;
        apt-get) printf 'fixture_apt\n' ;;
        *) trace "UNEXPECTED_TOOL:$1"; return 1 ;;
    esac
}
acfs_early_sudo_binary_path() { trace UNEXPECTED_SUDO; return 1; }
fixture_apt() { trace "apt:$*"; return 1; }
apt() { trace legacy_apt_list; return 1; }
state_upgrade_get_stage() { printf '%s\n' "$TEST_STAGE"; }
state_update() { trace state_update; return 0; }
state_load() { printf '{}\n'; }
state_ensure_valid() { trace state_validate; return 0; }
state_init() { trace state_init; return 0; }
upgrade_acquire_lock() { trace lock; return 0; }
upgrade_release_lock() { trace unlock; }
ubuntu_preflight_checks() { trace preflight; return 0; }
ubuntu_prepare_eol_repositories() { trace eol_prepare; return 0; }
ubuntu_start_upgrade_sequence() {
    trace "start:${UBUNTU_TARGET_VERSION}:${UBUNTU_TARGET_VERSION_NUM}:$*"
    local argument
    for argument in "$@"; do trace "startarg:$argument"; done
    trace "hops:$(ubuntu_calculate_upgrade_path | tr '\n' ',')"
    return 0
}
shutdown() { trace UNEXPECTED_SHUTDOWN; exit 98; }
reboot() { trace UNEXPECTED_REBOOT; exit 98; }
sleep() { trace UNEXPECTED_SLEEP; exit 98; }
'''
            settings = dict(TEST_VERSION=version, TEST_STAGE=stage, TARGET_UBUNTU_VERSION=target,
                            TARGET_UBUNTU_VERSION_EXPLICIT='true' if explicit else 'false',
                            SKIP_UBUNTU_UPGRADE='false', YES_MODE='true', ACFS_RESUME_DIR=directory,
                            ACFS_STATE_FILE='/preserved/original-state.json', SCRIPT_DIR=directory)
            assignments = '\n'.join(f'{key}={shlex.quote(value)}' for key, value in settings.items())
            call = 'run_ubuntu_upgrade_phase ' + ' '.join(map(shlex.quote, args))
            call = (f'if {call}; then rc=0; else rc=$?; fi\n'
                    'trace "restored:${ACFS_STATE_FILE-unset}"; exit "$rc"') if conditional else call
            # Redirect fixed OS reboot markers only in the in-memory test copy.
            # Production code has no environment-controlled path or bypass.
            functions = self.functions.replace('/var/run/reboot-required', str(path / 'reboot-required'))
            script = '\n'.join((prelude, self.policy, functions, assignments, overrides, call))
            def drop():
                os.setgroups([]); os.setgid(uid); os.setuid(uid)
            result = subprocess.run(['/bin/bash', '-p', '-s'], input=script, text=True,
                capture_output=True, timeout=10, env={'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'HOME': directory},
                preexec_fn=drop if uid is not None else None)
            events = [line.removeprefix('EVENT:') for line in result.stdout.splitlines() if line.startswith('EVENT:')]
            self.assertFalse(any('UNEXPECTED_' in event for event in events), result.stdout + result.stderr)
            return result.returncode, events, result.stderr

    @staticmethod
    def checkpoint(stage='not_started', target='26.04', **fields):
        upgrade = dict(enabled=stage not in ('not_started', 'completed'),
                       current_stage=stage, target_version=target)
        upgrade.update(fields)
        return json.dumps(dict(schema_version=3, ubuntu_upgrade=upgrade))

    def test_default_target_is_supported_lts(self):
        self.assertEqual(self.default, '26.04')

    def test_default_does_not_skip_a_fully_patched_lts(self):
        for version in ('22.04', '24.04'):
            with self.subTest(version=version):
                rc, events, errors = self.invoke(version=version, target=self.default, explicit=False)
                self.assertEqual(rc, 0, errors)
                self.assertTrue(any(e.startswith('start:26.04:2604:') for e in events), events)
                self.assertNotIn('legacy_apt_list', events)

    def test_requested_target_is_bound_before_library_load(self):
        for target in ('22.04', '24.04', '26.04'):
            with self.subTest(target=target):
                rc, events, errors = self.invoke(version=target, target=target)
                self.assertEqual(rc, 0, errors)
                self.assertIn(f'library:{target}:{target.replace(".", "")}', events)

    def test_inherited_library_target_cannot_replace_selected_target(self):
        rc, events, errors = self.invoke(overrides='UBUNTU_TARGET_VERSION=25.10; UBUNTU_TARGET_VERSION_NUM=9999')
        self.assertEqual(rc, 0, errors)
        self.assertIn('library:26.04:2604', events)

    def test_unsupported_targets_are_rejected_before_loading_or_packages(self):
        for target in ('25.10', '25.04', '24.10', '26.10', '26.04.1', '24', '', '026.04',
                       '26.04;false', 'x[$(id)]', '999999999999999999999.04'):
            with self.subTest(target=target):
                rc, events, _ = self.invoke(target=target)
                self.assertNotEqual(rc, 0)
                self.assertFalse(any(e.startswith(('library:', 'apt:', 'start:')) for e in events), events)

    def test_unsupported_sources_are_not_successful_noops(self):
        for source in ('20.04', '24.10', '25.04', '26.10', '28.04', 'malformed'):
            with self.subTest(source=source):
                rc, events, _ = self.invoke(version=source)
                self.assertNotEqual(rc, 0)
                self.assertFalse(any(e.startswith('start:') for e in events), events)

    def test_eol_source_cannot_be_accepted_as_a_newer_noop(self):
        for target in ('22.04', '24.04'):
            self.assertNotEqual(self.invoke(version='25.10', target=target)[0], 0)

    def test_supported_graph_delegates_correct_hops(self):
        for version, target, hops in (('22.04','26.04','24.04,26.04,'),
                                     ('24.04','26.04','26.04,'),
                                     ('25.10','26.04','26.04,'),
                                     ('22.04','24.04','24.04,')):
            with self.subTest(version=version, target=target):
                rc, events, errors = self.invoke(version=version, target=target)
                self.assertEqual(rc, 0, errors)
                self.assertIn('hops:' + hops, events)

    def test_supported_matching_or_higher_lts_is_noop(self):
        for version, target in (('26.04','26.04'),('24.04','24.04'),('22.04','22.04'),('26.04','24.04')):
            rc, events, errors = self.invoke(version=version, target=target)
            self.assertEqual(rc, 0, errors)
            self.assertFalse(any(e.startswith('start:') for e in events))
            self.assertIn('restored:/preserved/original-state.json', events)

    def test_library_failure_does_not_skip_upgrade(self):
        self.assertNotEqual(self.invoke(overrides='_source_ubuntu_upgrade_lib() { return 1; }')[0], 0)

    def test_version_probe_failure_is_fatal_under_both_call_styles(self):
        for conditional in (True, False):
            rc, events, _ = self.invoke(conditional=conditional,
                overrides='ubuntu_get_version_string() { return 7; }')
            self.assertNotEqual(rc, 0)
            self.assertFalse(any(e.startswith('start:') for e in events))

    def test_empty_or_failed_plans_never_allow_normal_install(self):
        for body in ('return 0', 'return 7', "printf '26.04\\n'; return 7"):
            for conditional in (True, False):
                with self.subTest(body=body, conditional=conditional):
                    rc, events, _ = self.invoke(conditional=conditional,
                        overrides='ubuntu_calculate_upgrade_path() { ' + body + '; }')
                    self.assertNotEqual(rc, 0)
                    self.assertFalse(any(e.startswith('start:') for e in events))

    def test_missing_executor_never_allows_normal_install(self):
        rc, events, _ = self.invoke(overrides='unset -f ubuntu_start_upgrade_sequence')
        self.assertNotEqual(rc, 0)
        self.assertIn('restored:/preserved/original-state.json', events)

    def test_executor_failure_releases_lock_and_restores_caller_state(self):
        rc, events, _ = self.invoke(overrides='ubuntu_start_upgrade_sequence() { trace executor_failed; return 9; }')
        self.assertNotEqual(rc, 0)
        self.assertIn('unlock', events)
        self.assertIn('restored:/preserved/original-state.json', events)

    def test_original_arguments_are_forwarded_literally(self):
        args = ('--yes','--mode','safe','--only','agents.codex','--skip-cloud','--target-ubuntu=26.04',
                '--ref','feature/release','--verified-installer-cache','/cache with spaces')
        rc, events, errors = self.invoke(args=args)
        self.assertEqual(rc, 0, errors)
        forwarded = [e.removeprefix('startarg:') for e in events if e.startswith('startarg:')]
        self.assertEqual(forwarded[1:], list(args))

    def test_explicit_skip_and_non_ubuntu_do_not_enter_upgrade(self):
        for override in ('SKIP_UBUNTU_UPGRADE=true', 'TEST_OS_ID=arch'):
            rc, events, errors = self.invoke(overrides=override)
            self.assertEqual(rc, 0, errors)
            self.assertFalse(any(e.startswith(('library:', 'apt:', 'start:')) for e in events), events)

    def test_process_local_archive_cannot_start_rebooting_upgrade(self):
        for override in ('BOOTSTRAP_ARCHIVE_PATH=/local/source.tar.gz', 'ACFS_LOCAL_ARCHIVE_SOURCE=true'):
            rc, events, _ = self.invoke(overrides=override)
            self.assertNotEqual(rc, 0)
            self.assertFalse(any(e.startswith('start:') for e in events))

    def test_every_active_checkpoint_blocks_even_fully_patched_lts(self):
        for stage in ('initializing', 'upgrading', 'awaiting_reboot', 'resumed', 'step_complete', 'error'):
            for explicit in (True, False):
                with self.subTest(stage=stage, explicit=explicit):
                    rc, events, _ = self.invoke(stage=stage, explicit=explicit)
                    self.assertNotEqual(rc, 0)
                    self.assertFalse(any(e.startswith(('start:', 'apt:', 'state_update')) for e in events))

    def test_completed_checkpoint_does_not_override_actual_os(self):
        rc, events, errors = self.invoke(version='25.10', stage='completed',
                                        state=self.checkpoint('completed', '25.10'))
        self.assertEqual(rc, 0, errors)
        self.assertIn('hops:26.04,', events)

    def test_malformed_checkpoint_is_preserved_not_reset(self):
        cases = ('', '{broken', '[]', 'null', '{}', '{"schema_version":4}',
                 '{"schema_version":3} {"schema_version":3}',
                 '{"schema_version":3,"ubuntu_upgrade":false}',
                 '{"schema_version":3,"ubuntu_upgrade":{}}',
                 self.checkpoint('upgrading', enabled=False),
                 self.checkpoint('unknown'), self.checkpoint(['not_started']),
                 self.checkpoint('not_started', needs_reboot='true'),
                 self.checkpoint('not_started', resume_after_reboot='true'),
                 self.checkpoint('completed', needs_reboot=True),
                 self.checkpoint('completed', resume_after_reboot=True),
                 self.checkpoint('completed', current_upgrade={'from':'24.04','to':'26.04'}))
        for state in cases:
            with self.subTest(state=state):
                rc, events, _ = self.invoke(state=state)
                self.assertNotEqual(rc, 0)
                self.assertFalse(any(e.startswith(('start:', 'apt:', 'state_update', 'state_init')) for e in events))
                self.assertIn('restored:/preserved/original-state.json', events)

    def test_prior_schema_without_upgrade_is_a_fresh_run(self):
        for schema in (1, 2, 3):
            rc, events, errors = self.invoke(state=json.dumps({'schema_version': schema}))
            self.assertEqual(rc, 0, errors)
            self.assertTrue(any(e.startswith('start:') for e in events))

    def test_unsafe_state_file_types_and_permissions_refused(self):
        for kind in ('symlink','hardlink','writable','fifo','directory','oversized','nonroot'):
            with self.subTest(kind=kind):
                state = self.checkpoint() if kind in ('hardlink','writable','nonroot') else None
                rc, events, _ = self.invoke(state=state, state_kind=kind)
                self.assertNotEqual(rc, 0)
                self.assertFalse(any(e.startswith(('apt:', 'state_update', 'start:')) for e in events))

    def test_missing_jq_never_causes_existing_state_to_be_ignored(self):
        override = 'acfs_early_system_binary_path() { case "$1" in jq) return 1 ;; stat) echo /usr/bin/stat ;; apt-get) echo fixture_apt ;; esac; }'
        rc, events, _ = self.invoke(state=self.checkpoint(), overrides=override)
        self.assertNotEqual(rc, 0)
        self.assertFalse(any(e.startswith(('apt:', 'start:')) for e in events))

    def test_noop_needs_neither_jq_install_nor_root(self):
        override = 'acfs_early_system_binary_path() { [[ "$1" != jq ]] || return 1; trace UNEXPECTED_TOOL; return 1; }'
        rc, events, errors = self.invoke(version='26.04', overrides=override, uid=65534)
        self.assertEqual(rc, 0, errors)
        self.assertFalse(any(e.startswith(('apt:', 'start:')) for e in events))

    def test_nonroot_upgrade_cannot_mutate_packages(self):
        override = 'acfs_early_system_binary_path() { case "$1" in jq) return 1 ;; apt-get) echo fixture_apt ;; esac; }'
        rc, events, _ = self.invoke(overrides=override, uid=65534)
        self.assertNotEqual(rc, 0)
        self.assertNotIn('lock', events)
        self.assertFalse(any(e.startswith(('apt:', 'start:')) for e in events))

    def test_bootstrap_source_refusal_precedes_jq_install(self):
        override = '''BOOTSTRAP_ARCHIVE_PATH=/local/source.tar.gz
acfs_early_system_binary_path() { case "$1" in jq) return 1 ;; apt-get) echo fixture_apt ;; esac; }'''
        rc, events, _ = self.invoke(overrides=override)
        self.assertNotEqual(rc, 0)
        self.assertFalse(any(e.startswith(('apt:', 'eol_prepare', 'start:')) for e in events))

    def test_missing_mandatory_functions_fail_before_lock_or_writes(self):
        for name in ('ubuntu_preflight_checks','ubuntu_start_upgrade_sequence','state_ensure_valid',
                     'state_load','state_init','state_update','upgrade_acquire_lock',
                     'upgrade_release_lock','ubuntu_prepare_eol_repositories'):
            with self.subTest(name=name):
                rc, events, _ = self.invoke(overrides='unset -f ' + name)
                self.assertNotEqual(rc, 0)
                self.assertNotIn('lock', events)
                self.assertFalse(any(e.startswith(('apt:', 'state_update', 'start:')) for e in events))

    def test_changed_stage_during_lock_acquisition_refused(self):
        override = '''upgrade_acquire_lock() {
    trace lock
    printf '%s' '{"schema_version":3,"ubuntu_upgrade":{"enabled":true,"current_stage":"upgrading","target_version":"26.04"}}' > "$ACFS_STATE_FILE"
}'''
        rc, events, _ = self.invoke(overrides=override)
        self.assertNotEqual(rc, 0)
        self.assertIn('unlock', events)
        self.assertFalse(any(e.startswith(('apt:', 'state_update', 'start:')) for e in events))

    def test_pre_reboot_checkpoint_target_cannot_silently_change(self):
        for recorded in ('25.10','24.04','28.04',''):
            rc, events, _ = self.invoke(state=self.checkpoint('pre_upgrade_reboot', recorded))
            self.assertNotEqual(rc, 0)
            self.assertNotIn('state_update', events)

    def test_checkpoint_is_not_cleared_if_lock_is_busy(self):
        rc, events, _ = self.invoke(stage='pre_upgrade_reboot',
            overrides='upgrade_acquire_lock() { trace busy; return 1; }')
        self.assertNotEqual(rc, 0)
        self.assertNotIn('state_update', events)
        self.assertNotIn('unlock', events)

    def test_checkpoint_is_not_cleared_if_preflight_fails(self):
        rc, events, _ = self.invoke(stage='pre_upgrade_reboot',
            overrides='ubuntu_preflight_checks() { trace preflight_failed; return 1; }')
        self.assertNotEqual(rc, 0)
        self.assertNotIn('state_update', events)
        self.assertIn('unlock', events)

    def test_checkpoint_clear_runs_under_lock_after_preflight(self):
        rc, events, errors = self.invoke(stage='pre_upgrade_reboot')
        self.assertEqual(rc, 0, errors)
        self.assertLess(events.index('lock'), events.index('state_update'))
        self.assertLess(events.index('preflight'), events.index('state_update'))
        self.assertLess(events.index('state_validate'), events.index('state_update'))

    def test_checkpoint_write_failure_blocks_executor(self):
        rc, events, _ = self.invoke(stage='pre_upgrade_reboot',
            overrides='state_update() { trace checkpoint_failed; return 1; }')
        self.assertNotEqual(rc, 0)
        self.assertIn('unlock', events)
        self.assertFalse(any(e.startswith('start:') for e in events))

    def test_pre_reboot_state_cannot_claim_completion_on_target_os(self):
        rc, events, _ = self.invoke(version='26.04', stage='pre_upgrade_reboot')
        self.assertNotEqual(rc, 0)
        self.assertNotIn('state_update', events)

    def test_state_pointer_unsetness_is_restored(self):
        rc, events, errors = self.invoke(version='26.04', overrides='unset ACFS_STATE_FILE')
        self.assertEqual(rc, 0, errors)
        self.assertIn('restored:unset', events)

    def jq_bootstrap(self, fault=''):
        return '''HAVE_JQ=false
acfs_early_system_binary_path() {
    case "$1" in
        jq) [[ "$HAVE_JQ" == true ]] || return 1; echo /usr/bin/jq ;;
        curl) echo /usr/bin/curl ;;
        stat) echo /usr/bin/stat ;;
        apt-get) echo fixture_apt ;;
        *) return 1 ;;
    esac
}
fixture_apt() {
    trace "apt:$*"
    if [[ "$*" == *"install -y jq"* ]]; then HAVE_JQ=true; fi
    return 0
}
''' + fault

    def test_eol_jq_bootstrap_holds_lock_and_recovers_sources_first(self):
        rc, events, errors = self.invoke(version='25.10', overrides=self.jq_bootstrap())
        self.assertEqual(rc, 0, errors)
        update = next(e for e in events if e.startswith('apt:') and 'update -qq' in e)
        install = next(e for e in events if e.startswith('apt:') and 'install -y jq' in e)
        self.assertIn('APT::Update::Error-Mode=any', update)
        self.assertIn('DPkg::Lock::Timeout=120', update)
        self.assertLess(events.index('lock'), events.index('eol_prepare'))
        self.assertLess(events.index('eol_prepare'), events.index(update))
        self.assertLess(events.index(update), events.index(install))

    def test_eol_repository_failure_stops_before_apt(self):
        rc, events, _ = self.invoke(version='25.10', overrides=self.jq_bootstrap(
            'ubuntu_prepare_eol_repositories() { trace eol_failed; return 1; }'))
        self.assertNotEqual(rc, 0)
        self.assertFalse(any(e.startswith('apt:') for e in events))
        self.assertIn('unlock', events)

    def test_jq_install_failure_or_missing_binary_cannot_start_upgrade(self):
        for fault in ('fixture_apt() { trace "apt:$*"; return 1; }',
                      'fixture_apt() { trace "apt:$*"; return 0; }',
                      'fixture_apt() { trace "apt:$*"; [[ "$*" != *"install -y jq"* ]]; }'):
            with self.subTest(fault=fault):
                rc, events, _ = self.invoke(overrides=self.jq_bootstrap(fault))
                self.assertNotEqual(rc, 0)
                self.assertIn('unlock', events)
                self.assertFalse(any(e.startswith('start:') for e in events))

    def minimal_bootstrap(self, *, jq_available=True, curl_available=False, fault=''):
        return f'HAVE_JQ={str(jq_available).lower()}; HAVE_CURL={str(curl_available).lower()}\n' + r'''
acfs_early_system_binary_path() {
    case "$1" in
        jq) [[ "$HAVE_JQ" == true ]] || return 1; echo /usr/bin/jq ;;
        curl) [[ "$HAVE_CURL" == true ]] || return 1; echo /usr/bin/curl ;;
        stat|mkdir) printf '/usr/bin/%s\n' "$1" ;;
        apt-get) echo fixture_apt ;;
        *) return 1 ;;
    esac
}
fixture_apt() {
    trace "apt:$*"
    if [[ " $* " == *" install "* ]]; then
        [[ " $* " != *" jq "* ]] || HAVE_JQ=true
        [[ " $* " != *" curl "* ]] || HAVE_CURL=true
    fi
    return 0
}
ubuntu_preflight_checks() {
    trace preflight
    [[ "$HAVE_JQ" == true && "$HAVE_CURL" == true ]]
}
''' + fault

    def test_minimal_host_bootstraps_only_missing_upgrade_tools_before_preflight(self):
        for jq_available, curl_available, packages in ((True, False, 'curl'),
                (False, True, 'jq'), (False, False, 'jq curl')):
            for version in ('22.04', '24.04', '25.10'):
                with self.subTest(jq=jq_available, curl=curl_available, version=version):
                    rc, events, errors = self.invoke(version=version, overrides=self.minimal_bootstrap(
                        jq_available=jq_available, curl_available=curl_available))
                    self.assertEqual(rc, 0, errors)
                    install = 'apt:-o DPkg::Lock::Timeout=120 install -y ' + packages
                    self.assertIn(install, events)
                    self.assertLess(events.index('lock'), events.index('eol_prepare'))
                    self.assertLess(events.index('eol_prepare'), events.index(install))
                    self.assertLess(events.index(install), events.index('preflight'))
                    self.assertEqual(sum('install -y' in e for e in events), 1)

    def test_existing_upgrade_tools_do_not_trigger_dependency_install(self):
        rc, events, errors = self.invoke(overrides=self.minimal_bootstrap(curl_available=True))
        self.assertEqual(rc, 0, errors)
        self.assertFalse(any(e.startswith('apt:') for e in events))

    def test_missing_curl_cannot_be_hidden_by_successful_package_exit(self):
        for fault in ('fixture_apt() { trace "apt:$*"; return 0; }',
                      'fixture_apt() { trace "apt:$*"; return 7; }',
                      'ubuntu_prepare_eol_repositories() { trace eol_failed; return 1; }'):
            with self.subTest(fault=fault):
                rc, events, _ = self.invoke(overrides=self.minimal_bootstrap(fault=fault))
                self.assertNotEqual(rc, 0)
                self.assertIn('unlock', events)
                self.assertNotIn('preflight', events)
                self.assertFalse(any(e.startswith('start:') for e in events))

    @staticmethod
    def reboot_setup(fault=''):
        return r'''
state_update_with_args() {
    trace record_reboot
    local filter="$1"; shift
    /usr/bin/jq -n "$@" "$filter | .schema_version=3" > "$SCRIPT_DIR/recorded-state.json" || return 1
    trace "recorded:$(/usr/bin/jq -r '[.ubuntu_upgrade.current_stage,.ubuntu_upgrade.original_version,.ubuntu_upgrade.target_version] | join(":")' "$SCRIPT_DIR/recorded-state.json")"
}
upgrade_setup_infrastructure() {
    trace infrastructure
    for argument in "$@"; do trace "resume_arg:$argument"; done
}
upgrade_update_motd() { trace motd; }
sleep() { trace "sleep:$*"; return 0; }
shutdown() { trace "shutdown:$*"; return 0; }
''' + fault

    def test_pending_kernel_reboot_records_target_and_preserves_resume_arguments(self):
        args = ('--yes', '--mode', 'safe', '--ref', 'v0.9.0', '--only', 'lang.bun',
                '--target-ubuntu=26.04', '--verified-installer-cache', '/cache path')
        rc, events, errors = self.invoke(reboot_required=True, overrides=self.reboot_setup(), args=args)
        self.assertEqual(rc, 0, errors)
        self.assertIn('recorded:pre_upgrade_reboot:24.04:26.04', events)
        self.assertLess(events.index('lock'), events.index('record_reboot'))
        self.assertLess(events.index('record_reboot'), events.index('infrastructure'))
        shutdown = next(e for e in events if e.startswith('shutdown:'))
        self.assertLess(events.index('infrastructure'), events.index(shutdown))
        for arg in args:
            self.assertIn('resume_arg:' + arg, events)
        self.assertNotIn('preflight', events)
        self.assertFalse(any(e.startswith('start:') for e in events))

    def test_reboot_request_failure_preserves_state_and_returns_nonzero(self):
        for conditional in (True, False):
            for code in (1, 17, 130):
                with self.subTest(conditional=conditional, code=code):
                    rc, events, _ = self.invoke(reboot_required=True, conditional=conditional,
                        overrides=self.reboot_setup(f'shutdown() {{ trace shutdown_failed; return {code}; }}'))
                    self.assertNotEqual(rc, 0)
                    self.assertIn('recorded:pre_upgrade_reboot:24.04:26.04', events)
                    self.assertIn('unlock', events)
                    self.assertNotIn('state_update', events)
                    self.assertFalse(any(e.startswith('start:') for e in events))

    def test_interrupted_reboot_delay_does_not_schedule_reboot(self):
        rc, events, _ = self.invoke(reboot_required=True,
            overrides=self.reboot_setup('sleep() { trace delay_interrupted; return 130; }'))
        self.assertNotEqual(rc, 0)
        self.assertIn('record_reboot', events)
        self.assertIn('unlock', events)
        self.assertFalse(any(e.startswith('shutdown:') for e in events))

    def test_reboot_never_runs_if_recovery_setup_fails(self):
        for fault in ('state_ensure_valid() { trace bad_state; return 1; }',
                      'state_update_with_args() { trace write_failed; return 1; }',
                      'upgrade_setup_infrastructure() { trace infrastructure_failed; return 1; }',
                      'unset -f state_update_with_args', 'unset -f upgrade_setup_infrastructure'):
            with self.subTest(fault=fault):
                rc, events, _ = self.invoke(reboot_required=True, overrides=self.reboot_setup(fault))
                self.assertNotEqual(rc, 0)
                self.assertIn('unlock', events)
                self.assertFalse(any(e.startswith(('shutdown:', 'sleep:', 'start:')) for e in events))

    def test_reboot_refuses_missing_or_failed_persistent_directory_tool(self):
        for resolver in ('return 1', 'echo fixture_mkdir'):
            fault = '''acfs_early_system_binary_path() {
    case "$1" in
        jq|curl|stat) printf '/usr/bin/%s\\n' "$1" ;;
        mkdir) ''' + resolver + ''' ;;
        *) return 1 ;;
    esac
}
fixture_mkdir() { trace mkdir_failed; return 1; }
'''
            rc, events, _ = self.invoke(reboot_required=True, overrides=self.reboot_setup(fault))
            self.assertNotEqual(rc, 0)
            self.assertIn('unlock', events)
            self.assertNotIn('record_reboot', events)
            self.assertFalse(any(e.startswith('shutdown:') for e in events))

    def test_optional_motd_failure_does_not_change_valid_reboot_outcome(self):
        rc, events, errors = self.invoke(reboot_required=True,
            overrides=self.reboot_setup('upgrade_update_motd() { trace motd_failed; return 1; }'))
        self.assertEqual(rc, 0, errors)
        self.assertIn('motd_failed', events)
        self.assertTrue(any(e.startswith('shutdown:') for e in events))

    def test_pending_reboot_without_noninteractive_consent_stops(self):
        rc, events, _ = self.invoke(reboot_required=True, stage='pre_upgrade_reboot',
            overrides=self.reboot_setup('YES_MODE=false'))
        self.assertNotEqual(rc, 0)
        self.assertIn('unlock', events)
        self.assertNotIn('record_reboot', events)
        self.assertFalse(any(e.startswith('shutdown:') for e in events))

    def test_unreadable_os_release_does_not_use_inherited_identity(self):
        rc, events, _ = self.invoke(overrides='ID=ubuntu; source() { return 1; }')
        self.assertNotEqual(rc, 0)
        self.assertFalse(any(e.startswith(('library:', 'apt:', 'start:')) for e in events))

    def test_state_validation_failure_never_reinitializes_existing_evidence(self):
        rc, events, _ = self.invoke(state=self.checkpoint(),
            overrides='state_ensure_valid() { trace invalid_state; return 1; }')
        self.assertNotEqual(rc, 0)
        self.assertNotIn('state_init', events)
        self.assertIn('unlock', events)

    def test_library_failure_precedes_package_install_attempt(self):
        rc, events, _ = self.invoke(overrides=self.jq_bootstrap('_source_ubuntu_upgrade_lib() { return 1; }'))
        self.assertNotEqual(rc, 0)
        self.assertFalse(any(e.startswith(('apt:', 'eol_prepare', 'start:')) for e in events))

    def test_symlinked_state_parent_is_refused_before_mutation(self):
        override = '''mkdir "$SCRIPT_DIR/redirected"
ln -s "$SCRIPT_DIR/redirected" "$SCRIPT_DIR/link"
ACFS_RESUME_DIR="$SCRIPT_DIR/link"'''
        rc, events, _ = self.invoke(overrides=override)
        self.assertNotEqual(rc, 0)
        self.assertFalse(any(e.startswith(('apt:', 'state_update', 'state_init', 'start:')) for e in events))


if __name__ == '__main__':
    unittest.main(verbosity=2)
