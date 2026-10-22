#!/usr/bin/env python3
"""Execute PostgreSQL's authored installer/checks without touching the host.

The unit harness redirects fixed OS/APT/binary paths in memory and substitutes
package/network commands. It does not claim to install PostgreSQL. --live-package
is a separate acceptance probe for a fresh disposable Ubuntu container only.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
TEXT = (ROOT / 'acfs.manifest.yaml').read_text()
MODULE = TEXT.split('\n  - id: db.postgres18\n', 1)[1].split('\n  - id: ', 1)[0]


def block(start, end):
    lines = MODULE.split(start, 1)[1].split(end, 1)[0].splitlines()
    if not lines or any(line and not line.startswith('        ') for line in lines):
        raise ValueError('PostgreSQL authored block layout changed; update extraction explicitly')
    return '\n'.join(line[8:] for line in lines) + '\n'


INSTALL = block('    install:\n      - |\n', '    verify:\n')
CHECK = block('      command: |\n', '    install:\n')
VERIFY = block('    verify:\n      - |\n', '      - systemctl ')


def generated_check():
    """Read the same command that the installed skip-if-present helper uses."""
    return subprocess.check_output([
        '/bin/bash', '-p', '-euo', 'pipefail', '-c',
        'source "$1"; printf "%s" "${ACFS_MODULE_INSTALLED_CHECK[db.postgres18]}"',
        '_', str(ROOT / 'scripts/generated/manifest_index.sh'),
    ], text=True)


def generated_doctor_check():
    """Decode the actual generated doctor entry, which runs without errexit."""
    return subprocess.check_output([
        '/bin/bash', '-p', '-euo', 'pipefail', '-c',
        'source "$1"; for entry in "${MANIFEST_CHECKS[@]}"; do '
        'IFS=$\'\\t\' read -r id description command optional context <<< "$entry"; '
        'if [[ "$id" == db.postgres18.1 ]]; then printf "%b" "$command"; exit 0; fi; '
        'done; exit 1',
        '_', str(ROOT / 'scripts/generated/doctor_checks.sh'),
    ], text=True)


class PostgresInstallTests(unittest.TestCase):
    def setUp(self):
        # Retain failures/fixtures for inspection; no destructive cleanup.
        self.root = Path(tempfile.mkdtemp(prefix='acfs-postgres-test-'))
        self.apt = self.root / 'apt'
        self.apt.mkdir()
        self.release = self.root / 'os-release'
        self.binaries = self.root / 'pg-bin'
        self.binaries.mkdir()
        self.log = self.root / 'calls'
        self.key = self.apt / 'keyrings/postgresql.gpg'
        self.source = self.apt / 'sources.list.d/pgdg.list'
        self.os_release()
        self.env = dict(os.environ, TEST_ROOT=str(self.root), TEST_BIN=str(self.binaries),
                        TEST_LOG=str(self.log), LANG='C', LC_ALL='C')

    def os_release(self, version='26.04', codename='resolute', distro='ubuntu'):
        self.release.write_text(f'ID={distro}\nVERSION_ID="{version}"\nVERSION_CODENAME={codename}\n')

    def prepare_source(self, content):
        self.source.parent.mkdir(parents=True, exist_ok=True)
        self.source.write_text(content)

    def shell(self, body=INSTALL, code=0, errexit=True, **env):
        # Deliberate fixture substitution only: production has no path overrides.
        body = body.replace('/etc/os-release', str(self.release))
        body = body.replace('/etc/apt', str(self.apt))
        body = body.replace('/usr/lib/postgresql/18/bin', str(self.binaries))
        program = r'''set -euo pipefail
apt-get() {
    printf 'apt %s\n' "$*" >> "$TEST_LOG"
    case " $* " in
        *' update '*) return "${UPDATE_EXIT:-0}" ;;
        *' install '*) return "${INSTALL_EXIT:-0}" ;;
        *) return 90 ;;
    esac
}
curl() {
    printf 'curl %s\n' "$*" >> "$TEST_LOG"
    printf 'fixture-key\n'
    return "${CURL_EXIT:-0}"
}
gpg() {
    printf 'gpg %s\n' "$*" >> "$TEST_LOG"
    cat
    return "${GPG_EXIT:-0}"
}
dpkg-query() {
    printf 'dpkg %s\n' "$*" >> "$TEST_LOG"
    case "${*: -1}" in
        postgresql-18) printf '%s' "${SERVER_STATUS:-installed}"; return "${SERVER_EXIT:-0}" ;;
        postgresql-client-18) printf '%s' "${CLIENT_STATUS:-installed}"; return "${CLIENT_EXIT:-0}" ;;
        *) return 91 ;;
    esac
}
''' + ('' if errexit else 'set +e\n') + body
        result = subprocess.run(['/bin/bash', '-c', program],
                                env={**self.env, **env}, capture_output=True, text=True, timeout=5)
        if code == 0:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def binaries_for(self, server='18.6', client='18.6'):
        for name, version in [('postgres', server), ('psql', client)]:
            path = self.binaries / name
            path.write_text(f'#!/bin/sh\nprintf "%s\\n" "{name} (PostgreSQL) {version}"\n')
            path.chmod(0o755)

    def test_authored_blocks_have_valid_bash_and_root_installed_check(self):
        self.assertIn('installed_check:\n      run_as: root\n', MODULE)
        for body in (INSTALL, CHECK, VERIFY):
            subprocess.run(['/bin/bash', '-n'], input=body, text=True, check=True)

    def test_resolute_uses_native_exact_server_and_client_without_pgdg(self):
        self.shell()
        self.assertEqual(self.calls(), [
            'apt -o DPkg::Lock::Timeout=120 -o APT::Update::Error-Mode=any update',
            'apt -o DPkg::Lock::Timeout=120 --no-remove install -y postgresql-18 postgresql-client-18'])
        self.assertEqual(list(self.apt.iterdir()), [])

    def test_native_install_preserves_existing_operator_repository_files(self):
        self.prepare_source('operator-managed repository\n')
        before = self.source.read_bytes()
        self.shell()
        self.assertEqual(self.source.read_bytes(), before)
        self.assertFalse(self.key.exists())

    def test_each_older_lts_uses_its_own_signed_repository(self):
        for version, codename in [('22.04', 'jammy'), ('24.04', 'noble')]:
            with self.subTest(version=version):
                self.setUp()
                self.os_release(version, codename)
                self.shell()
                self.assertEqual(self.source.read_text(),
                    f'deb [signed-by={self.key}] https://apt.postgresql.org/pub/repos/apt {codename}-pgdg main\n')
                self.assertEqual(self.key.read_text(), 'fixture-key\n')
                self.assertEqual(self.key.stat().st_mode & 0o777, 0o644)
                self.assertEqual(self.source.stat().st_mode & 0o777, 0o644)
                self.assertTrue(any('--proto =https --proto-redir =https' in c for c in self.calls()))
                self.assertIn('--max-time 60', '\n'.join(self.calls()))
                self.assertTrue(self.calls()[-1].endswith('postgresql-18 postgresql-client-18'))

    def test_matching_pgdg_retry_does_not_download_or_rewrite_repository(self):
        self.os_release('24.04', 'noble')
        self.shell()
        before = [(p.read_bytes(), p.stat().st_mtime_ns, p.stat().st_ino) for p in (self.key, self.source)]
        first = len(self.calls())
        self.shell()
        self.assertEqual([(p.read_bytes(), p.stat().st_mtime_ns, p.stat().st_ino) for p in (self.key, self.source)], before)
        self.assertTrue(all(c.startswith('apt ') for c in self.calls()[first:]))

    def test_unsupported_or_incoherent_release_fails_before_network_or_mutation(self):
        for version, codename, distro in [
            ('25.10', 'questing', 'ubuntu'), ('25.04', 'plucky', 'ubuntu'),
            ('24.10', 'oracular', 'ubuntu'), ('20.04', 'focal', 'ubuntu'),
            ('26.10', 'stonking', 'ubuntu'), ('26.04', 'noble', 'ubuntu'),
            ('24.04', 'resolute', 'ubuntu'), ('26.04', 'resolute', 'debian'),
        ]:
            with self.subTest(version=version, codename=codename, distro=distro):
                self.os_release(version, codename, distro)
                self.shell(code=1)
                self.assertEqual(self.calls(), [])
                self.assertEqual(list(self.apt.iterdir()), [])

    def test_missing_os_fields_cannot_be_supplied_by_inherited_environment(self):
        self.release.write_text('ID=ubuntu\n')
        self.shell(code=1, VERSION_ID='26.04', VERSION_CODENAME='resolute')
        self.assertEqual(self.calls(), [])

    def test_absent_os_metadata_fails_before_any_package_commands(self):
        self.release.rename(self.root / 'release.saved')
        self.shell(code=1)
        self.assertEqual(self.calls(), [])

    def test_conflicting_repository_is_preserved_without_retargeting(self):
        self.os_release('22.04', 'jammy')
        self.prepare_source(f'deb [signed-by={self.key}] https://apt.postgresql.org/pub/repos/apt noble-pgdg main\n')
        before = self.source.read_bytes()
        self.shell(code=1)
        self.assertEqual(self.source.read_bytes(), before)
        self.assertEqual(self.calls(), [])
        self.assertFalse(self.key.exists())

    def test_symlinked_key_source_or_parent_is_refused_before_network(self):
        for relative in ('keyrings', 'sources.list.d', 'keyrings/postgresql.gpg', 'sources.list.d/pgdg.list'):
            with self.subTest(relative=relative):
                self.setUp()
                self.os_release('24.04', 'noble')
                target = self.apt / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                saved = self.root / 'untouched'
                saved.write_text('keep')
                target.symlink_to(saved)
                self.shell(code=1)
                self.assertEqual(saved.read_text(), 'keep')
                self.assertEqual(self.calls(), [])

    def test_hardlinked_repository_and_key_are_refused(self):
        for relative in ('keyrings/postgresql.gpg', 'sources.list.d/pgdg.list'):
            with self.subTest(relative=relative):
                self.setUp()
                self.os_release('24.04', 'noble')
                target = self.apt / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('keep')
                os.link(target, self.root / 'link')
                self.shell(code=1)
                self.assertEqual(target.read_text(), 'keep')
                self.assertEqual(self.calls(), [])

    def test_fifo_source_is_refused_without_blocking(self):
        self.os_release('24.04', 'noble')
        self.source.parent.mkdir()
        os.mkfifo(self.source)
        self.shell(code=1)
        self.assertEqual(self.calls(), [])

    def test_failed_download_or_key_decode_never_publishes_trust_inputs(self):
        for env in ({'CURL_EXIT': '22'}, {'GPG_EXIT': '2'}):
            with self.subTest(env=env):
                self.setUp()
                self.os_release('24.04', 'noble')
                self.shell(code=1, **env)
                self.assertFalse(self.key.exists())
                self.assertFalse(self.source.exists())
                self.assertFalse(any(c.startswith('apt ') for c in self.calls()))

    def test_failed_metadata_refresh_stops_before_package_install(self):
        self.shell(code=1, UPDATE_EXIT='100')
        self.assertEqual(len(self.calls()), 1)
        self.assertTrue(self.calls()[0].endswith(' update'))

    def test_install_failure_never_falls_back_to_another_database_major(self):
        self.shell(code=1, INSTALL_EXIT='100')
        self.assertEqual(len(self.calls()), 2)
        self.assertNotIn('noble', '\n'.join(self.calls()))
        self.assertFalse(any(c.endswith('install -y postgresql') for c in self.calls()))

    def test_installed_requires_both_fully_configured_packages(self):
        self.binaries_for()
        for env in ({'SERVER_EXIT': '1'}, {'CLIENT_EXIT': '1'},
                    {'SERVER_STATUS': 'unpacked'}, {'CLIENT_STATUS': 'half-configured'},
                    {'SERVER_STATUS': 'config-files'}):
            with self.subTest(env=env):
                self.shell(CHECK, code=1, **env)
        self.shell(CHECK)

    def test_client_alone_or_old_major_does_not_skip_the_server(self):
        self.binaries_for('17.6', '18.6')
        self.shell(CHECK, code=1)
        self.binaries_for('18.6', '16.9')
        self.shell(CHECK, code=1)
        self.binaries_for('18.6', '18.6')
        (self.binaries / 'postgres').rename(self.binaries / 'postgres.saved')
        self.shell(CHECK, code=1)

    def test_installed_check_ignores_ambient_psql_from_path(self):
        self.binaries_for()
        fake = self.root / 'psql'
        fake.write_text('#!/bin/sh\nexit 99\n')
        fake.chmod(0o755)
        self.shell(CHECK, PATH=f'{self.root}:/usr/bin:/bin')

    def test_generated_installed_check_preserves_source_and_real_exit_status(self):
        emitted = generated_check()
        self.assertEqual(emitted, CHECK)
        self.binaries_for()
        self.shell(emitted)
        self.shell(emitted, code=1, SERVER_EXIT='1')
        self.shell(emitted, code=1, CLIENT_STATUS='unpacked')

    def test_generated_installed_check_does_not_accept_older_server_or_client(self):
        emitted = generated_check()
        self.binaries_for('17.6', '18.6')
        self.shell(emitted, code=1)
        self.binaries_for('18.6', '17.6')
        self.shell(emitted, code=1)
        self.binaries_for()
        self.shell(emitted)

    def test_doctor_cannot_hide_a_failed_server_check_behind_a_working_client(self):
        # The doctor runner uses pipefail, not errexit. A later successful
        # client probe must not erase a missing/wrong-major server failure.
        for body in (VERIFY, generated_doctor_check()):
            self.binaries_for('17.6', '18.6')
            self.shell(body, code=1, errexit=False)
            (self.binaries / 'postgres').rename(self.binaries / 'postgres.saved')
            self.shell(body, code=1, errexit=False)
            self.binaries_for()
            self.shell(body, errexit=False)

    def test_generated_doctor_requires_both_packages_and_client_major(self):
        emitted = generated_doctor_check()
        self.assertEqual(emitted, VERIFY.rstrip('\n'))
        self.binaries_for('18.6', '17.6')
        self.shell(emitted, code=1, errexit=False)
        self.binaries_for()
        self.shell(emitted, code=1, errexit=False, SERVER_EXIT='1')
        self.shell(emitted, code=1, errexit=False, CLIENT_STATUS='unpacked')
        self.shell(emitted, errexit=False)


class PostgresRecoveryTests(unittest.TestCase):
    """Run the authored service recovery logic with local command fixtures."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='acfs-postgres-recovery-'))
        self.data = self.root / 'data'
        self.data.mkdir()
        self.log = self.root / 'calls'
        self.clusters = self.root / 'clusters'
        self.clusters.write_text('')
        source = (ROOT / 'install.sh').read_text()
        functions = []
        for name in ('acfs_postgres_run_as_owner', 'acfs_postgres_query',
                     'acfs_postgres_ready', 'acfs_postgres_start_existing',
                     'acfs_arch_install_postgres'):
            start = source.index(f'\n{name}() {{\n') + 1
            end = source.index('\n}\n', start) + 3
            functions.append(source[start:end])
        self.authored = '\n'.join(functions).replace('/var/lib/postgres/data', str(self.data))
        self.authored = self.authored.replace('/run/systemd/system', str(self.root / 'systemd'))

    def shell(self, command, code=0, **env):
        fixtures = r'''set -euo pipefail
SUDO=''
ACFS_DISTRO_FAMILY="${FAMILY:-arch}"
acfs_early_system_binary_path() {
    case "$1" in
        runuser) printf '%s\n' fixture_owner ;;
        env) printf '%s\n' fixture_env ;;
        psql) printf '%s\n' fixture_psql ;;
        pg_lsclusters) printf '%s\n' fixture_clusters ;;
        pg_ctlcluster) printf '%s\n' fixture_control ;;
        pg_createcluster) printf '%s\n' fixture_create ;;
        pg_ctl) printf '%s\n' fixture_pg_ctl ;;
        *) return 1 ;;
    esac
}
acfs_early_sudo_binary_path() { printf '%s\n' fixture_owner; }
fixture_owner() {
    printf 'owner %s\n' "$*" >> "$TEST_LOG"
    while [[ "$1" != -- ]]; do shift; done
    shift
    "$@"
}
fixture_env() {
    while [[ "$1" == -u ]]; do unset "$2"; shift 2; done
    while [[ "$1" == *=* ]]; do export "$1"; shift; done
    "$@"
}
fixture_psql() {
    printf 'query %s\n' "$*" >> "$TEST_LOG"
    [[ -z "${PGHOST:-}${PGSERVICE:-}${PGSERVICEFILE:-}${PGOPTIONS:-}${PGPASSWORD:-}" ]] || return 91
    [[ "${PGCONNECT_TIMEOUT:-}" == 5 ]] || return 92
    local port=''
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == -p ]]; then port="$2"; shift; fi
        shift
    done
    [[ -f "$TEST_ROOT/running.$port" ]] || return 2
    printf '%s\n' "${QUERY_OUTPUT:-1}"
    return "${QUERY_EXIT:-0}"
}
fixture_clusters() {
    local version name port status rest
    while read -r version name port status rest; do
        [[ -n "$version" ]] || continue
        if [[ -f "$TEST_ROOT/running.$port" ]]; then status=online; fi
        printf '%s %s %s %s %s\n' "$version" "$name" "$port" "$status" "$rest"
    done < "$TEST_ROOT/clusters"
}
fixture_control() {
    printf 'cluster-start %s\n' "$*" >> "$TEST_LOG"
    [[ "${START_EXIT:-0}" == 0 ]] || return "$START_EXIT"
    local version name port status rest
    while read -r version name port status rest; do
        if [[ "$version" == "$1" && "$name" == "$2" && "${START_MAKES_READY:-1}" == 1 ]]; then
            touch "$TEST_ROOT/running.$port"
        fi
    done < "$TEST_ROOT/clusters"
}
fixture_create() {
    printf 'cluster-create %s\n' "$*" >> "$TEST_LOG"
    [[ "${CREATE_EXIT:-0}" == 0 ]] || return "$CREATE_EXIT"
    printf '18 main 5433 online postgres fixture fixture.log\n' >> "$TEST_ROOT/clusters"
    touch "$TEST_ROOT/running.5433"
}
fixture_pg_ctl() {
    printf 'server-start %s\n' "$*" >> "$TEST_LOG"
    [[ "${START_EXIT:-0}" == 0 ]] || return "$START_EXIT"
    [[ "${START_MAKES_READY:-1}" == 1 ]] && touch "$TEST_ROOT/running.5432"
    return 0
}
pacman() { [[ "${SERVER_INSTALLED:-1}" == 1 ]]; }
acfs_arch_pkg_install() {
    printf 'package-install %s\n' "$*" >> "$TEST_LOG"
    [[ "${INSTALL_EXIT:-0}" == 0 ]] || return "$INSTALL_EXIT"
    SERVER_INSTALLED=1
}
initdb() {
    printf 'initdb %s\n' "$*" >> "$TEST_LOG"
    [[ "${INITDB_EXIT:-0}" == 0 ]] || return "$INITDB_EXIT"
    printf '18\n' > "$TEST_ROOT/data/PG_VERSION"
}
try_step() { shift; "$@"; }
try_step_eval() { printf 'prepare-data\n' >> "$TEST_LOG"; return "${PREPARE_EXIT:-0}"; }
acfs_postgres_bootstrap_role() { printf 'bootstrap-role\n' >> "$TEST_LOG"; }
acfs_use_generated_category() { [[ "${GENERATED_DB:-false}" == true ]]; }
acfs_verify_module_commands() { [[ "${PACKAGE_VALID:-1}" == 1 ]]; }
command_exists() { return 1; }
log_warn() { :; }
'''
        result = subprocess.run(['/bin/bash', '-c', fixtures + '\n' + self.authored + '\n' + command],
                                env={**os.environ, 'TEST_ROOT': str(self.root),
                                     'TEST_LOG': str(self.log), **env},
                                capture_output=True, text=True, timeout=5)
        if code == 0:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def initialized(self):
        (self.data / 'PG_VERSION').write_text('18\n')

    def test_client_alone_never_satisfies_arch_server_readiness(self):
        (self.root / 'running.5432').touch()
        self.shell('acfs_postgres_ready', code=1, SERVER_INSTALLED='0')
        self.assertEqual(self.calls(), [])
        self.shell('acfs_postgres_ready', code=1)
        self.assertEqual(self.calls(), [])

    def test_stopped_arch_server_recovers_without_reinstalling_or_reinitializing(self):
        self.initialized()
        self.shell('acfs_arch_install_postgres; acfs_postgres_start_existing')
        calls = self.calls()
        self.assertEqual(sum(c.startswith('server-start ') for c in calls), 1)
        self.assertFalse(any(c.startswith(('package-install ', 'initdb ')) for c in calls))
        self.assertTrue(any('-u postgres -- fixture_pg_ctl' in c for c in calls))
        self.assertEqual((self.data / 'PG_VERSION').read_text(), '18\n')

    def test_failed_initdb_stops_before_service_start(self):
        self.shell('acfs_arch_install_postgres', code=1, INITDB_EXIT='1')
        self.assertTrue(any(c.startswith('initdb ') for c in self.calls()))
        self.assertFalse(any(c.startswith(('server-start ', 'bootstrap-role')) for c in self.calls()))
        self.assertFalse((self.data / 'PG_VERSION').exists())

    def test_start_failure_cannot_be_overwritten_by_later_success(self):
        self.initialized()
        self.shell('acfs_arch_install_postgres', code=1, START_EXIT='1')
        self.assertFalse(any(c == 'bootstrap-role' for c in self.calls()))

    def test_successful_start_command_still_requires_a_working_database(self):
        self.initialized()
        self.shell('acfs_arch_install_postgres', code=1, START_MAKES_READY='0')
        self.assertTrue(any(c.startswith('server-start ') for c in self.calls()))
        self.assertFalse(any(c == 'bootstrap-role' for c in self.calls()))

    def test_pg18_recovery_uses_correct_cluster_and_its_port(self):
        self.clusters.write_text('17 main 5432 online postgres old old.log\n'
                                 '18 work 5441 down postgres current current.log\n')
        (self.root / 'running.5432').touch()
        self.shell('acfs_postgres_start_existing', FAMILY='ubuntu', GENERATED_DB='true')
        calls = self.calls()
        self.assertEqual([c for c in calls if c.startswith('cluster-start ')],
                         ['cluster-start 18 work start'])
        self.assertTrue(any('-p 5441 ' in c for c in calls if c.startswith('query ')))
        self.assertFalse(any('-p 5432 ' in c for c in calls if c.startswith('query ')))
        self.assertFalse(any(c.startswith(('package-install ', 'cluster-create ')) for c in calls))

    def test_other_major_cannot_hide_missing_pg18_cluster(self):
        self.clusters.write_text('17 main 5432 online postgres old old.log\n')
        (self.root / 'running.5432').touch()
        self.shell('acfs_postgres_ready', code=1, FAMILY='ubuntu', GENERATED_DB='true')
        self.shell('acfs_postgres_start_existing', code=1, FAMILY='ubuntu',
                   GENERATED_DB='true', PACKAGE_VALID='0')
        self.assertFalse(any(c.startswith(('query ', 'cluster-create ')) for c in self.calls()))

    def test_missing_pg18_cluster_is_created_only_after_package_verification(self):
        self.shell('acfs_postgres_start_existing', FAMILY='ubuntu', GENERATED_DB='true')
        self.assertIn('cluster-create 18 main --start', self.calls())
        self.assertTrue(any('-p 5433 ' in c for c in self.calls() if c.startswith('query ')))

    def test_failed_cluster_creation_is_not_a_successful_repair(self):
        self.shell('acfs_postgres_start_existing', code=1, FAMILY='ubuntu',
                   GENERATED_DB='true', CREATE_EXIT='1')
        self.assertEqual(self.calls(), ['cluster-create 18 main --start'])

    def test_query_uses_local_socket_and_removes_remote_connection_settings(self):
        self.initialized()
        (self.root / 'running.5432').touch()
        self.shell('acfs_postgres_ready', PGHOST='remote.example', PGSERVICE='remote',
                   PGSERVICEFILE='/untrusted/service', PGOPTIONS='untrusted', PGPASSWORD='fixture')
        query = next(c for c in self.calls() if c.startswith('query '))
        self.assertIn('-X -h /var/run/postgresql -p 5432 -U postgres -d postgres -Atqc SELECT 1', query)
        self.shell('acfs_postgres_ready', code=1, QUERY_OUTPUT='0')


def live_package():
    """Fresh disposable Ubuntu only: install and query a real PostgreSQL 18 server."""
    if os.environ.get('ACFS_POSTGRES_DISPOSABLE') != '1' or os.geteuid() != 0:
        raise RuntimeError('Requires ACFS_POSTGRES_DISPOSABLE=1 as root in a fresh disposable Ubuntu container')
    check = generated_check()
    if check != CHECK:
        raise RuntimeError('Generated installed-check command differs from its authored source')
    # Run the actual installed check before provisioning. A client-only fixture
    # or the old Ubuntu default server must not satisfy this module.
    before = subprocess.run(['/bin/bash', '-euo', 'pipefail', '-c', check]).returncode
    if before == 0:
        raise RuntimeError('Expected a fresh image without both PostgreSQL 18 packages')
    subprocess.run(['/bin/bash', '-euo', 'pipefail', '-c', INSTALL], check=True)
    subprocess.run(['/bin/bash', '-euo', 'pipefail', '-c', check], check=True)
    # A second package invocation must be safe; never upgrade old clusters.
    subprocess.run(['/bin/bash', '-euo', 'pipefail', '-c', INSTALL], check=True)
    subprocess.run(['/bin/bash', '-euo', 'pipefail', '-c', check], check=True)
    clusters = subprocess.check_output(['pg_lsclusters', '--no-header'], text=True).splitlines()
    main = [c.split() for c in clusters if c.split()[:2] == ['18', 'main']]
    if len(main) != 1:
        raise RuntimeError('Package installation did not create the expected disposable cluster')
    if main[0][3] != 'online':
        subprocess.run(['pg_ctlcluster', '18', 'main', 'start'], check=True)
    command = ['runuser', '-u', 'postgres', '--', '/usr/lib/postgresql/18/bin/psql',
               '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-p', main[0][2], '-d', 'postgres']
    version = subprocess.check_output(command + ['-c', 'SHOW server_version_num'], text=True).strip()
    if not version.isdigit() or int(version) // 10000 != 18:
        raise RuntimeError('Connected server is not PostgreSQL 18')
    result = subprocess.check_output(command + ['-c',
        'BEGIN; CREATE TEMP TABLE acfs_probe(value integer); INSERT INTO acfs_probe VALUES (42); '
        'SELECT value FROM acfs_probe; ROLLBACK;'], text=True)
    if '42' not in result.splitlines():
        raise RuntimeError('Actual database round trip failed')
    print(json.dumps({'postgresql_major': 18, 'package_install': 'pass', 'repeat_install': 'pass',
                      'server_query': 'pass', 'transaction_round_trip': 'pass'}))


if __name__ == '__main__':
    if sys.argv[1:] == ['--live-package']:
        live_package()
    else:
        unittest.main(verbosity=2)
