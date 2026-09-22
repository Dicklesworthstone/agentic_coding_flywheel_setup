#!/usr/bin/env python3
"""Real Bash progress-state tests with explicit filesystem/helper fixtures.

No installer, provider, rollback, or git commit is executed. Temporary fixtures
are retained for inspection. Run with Python's unittest runner or directly.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/lib/newproj_screens/screen_progress.sh"
BASH = shutil.which("bash")

HARNESS = r'''
set -euo pipefail
source "$SCRIPT"
declare -A values=(
    [project_dir]="$PROJECT" [project_name]=myapp [tech_stack]=python
    [agents_md_custom]="" [enable_agents]=true [enable_br]=true
    [enable_claude]=true [enable_ubsignore]=true
)
state_get() { printf '%s\n' "${values[$1]:-}"; }
log_info() { :; }
log_warn() { printf '%s\n' "$*" >&2; }
newproj_tty_printf() { printf "$@" >&2; }
render_progress_screen_best_effort() { :; }
begin_project_creation() { WIZARD_TRANSACTION_ACTIVE=true; }
suspend_project_creation_cleanup() { WIZARD_TRANSACTION_ACTIVE=false; }
commit_project_creation() { WIZARD_TRANSACTION_ACTIVE=false; }
rollback_project_creation() { echo ROLLBACK >> "$EVENTS"; return 97; }
# Any active legacy cleanup trap is a test failure, even when Bash exits under
# errexit or a signal interrupts the next external helper.
trap 'if [[ "${WIZARD_TRANSACTION_ACTIVE:-false}" == true ]]; then echo CLEANUP >> "$EVENTS"; fi' EXIT
try_create_directory() { mkdir -p -- "$1"; }
try_git_init() { mkdir -- "$1/.git"; }
try_br_init() { mkdir -- "$1/.beads"; }
try_write_file() {
    [[ ! -e "$1" && ! -L "$1" ]] || return 19
    mkdir -p -- "$(dirname -- "$1")"
    (set -o noclobber; printf '%s' "$2" > "$1")
}
newproj_has_existing_claude_settings() { [[ -f "$1/.claude/settings.local.json" ]]; }
generate_agents_md() { printf '# Reviewed policy for %s\n' "$1"; }
# A command fixture counts side effects without changing production code.
original_execute_step=$(declare -f execute_step)
eval "${original_execute_step/execute_step/original_execute_step}"
FAIL_STEP=create_gitignore
execute_step() {
    printf '%s\n' "$1" >> "$EVENTS"
    if [[ "$1" == "$FAIL_STEP" ]]; then return 23; fi
    original_execute_step "$1"
}
'''

@unittest.skipUnless(BASH, "Bash is required")
class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="acfs-progress-"))
        self.project = self.root / "project ' quoted; [literal]"
        self.events = self.root / "events"
        self.env = {**os.environ, "SCRIPT": str(SCRIPT), "PROJECT": str(self.project),
                    "EVENTS": str(self.events), "ACFS_TEST_MODE": "1"}

    def run_shell(self, body, data=""):
        result = subprocess.run([BASH, "-c", HARNESS + body], env=self.env,
                                input=data, text=True, capture_output=True,
                                cwd=self.root, timeout=10, start_new_session=True)
        return result

    def events_read(self):
        return self.events.read_text().splitlines() if self.events.exists() else []

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("ROLLBACK", self.events_read())
        self.assertNotIn("CLEANUP", self.events_read())

    def test_failure_retains_completed_files(self):
        result = self.run_shell('if run_creation; then exit 91; fi')
        self.assert_success(result)
        self.assertTrue((self.project / "README.md").is_file())
        self.assertTrue((self.project / ".git").is_dir())
        self.assertIn("Project preserved", result.stderr)

    def test_retry_continues_without_recreating_completed_work(self):
        result = self.run_shell('''
            if run_creation; then exit 91; fi
            printf 'my own work' > "$PROJECT/user.txt"
            FAIL_STEP=''
            run_creation
            [[ "${STEP_STATUS[finalize]}" == success ]]
        ''')
        self.assert_success(result)
        self.assertEqual(self.events_read().count("create_dir"), 1)
        self.assertEqual(self.events_read().count("init_git"), 1)
        self.assertEqual(self.events_read().count("create_readme"), 1)
        self.assertEqual(self.events_read().count("create_gitignore"), 2)
        self.assertEqual((self.project / "user.txt").read_text(), "my own work")

    def test_repeated_failures_keep_the_same_completed_steps(self):
        result = self.run_shell('''
            for attempt in 1 2 3; do if run_creation; then exit 91; fi; done
            FAIL_STEP=''
            run_creation
        ''')
        self.assert_success(result)
        self.assertEqual(self.events_read().count("create_readme"), 1)
        self.assertEqual(self.events_read().count("create_gitignore"), 4)

    def test_completed_run_is_not_replayed(self):
        result = self.run_shell("FAIL_STEP=''; run_creation; run_creation")
        self.assert_success(result)
        self.assertEqual(self.events_read().count("finalize"), 1)

    def test_changed_settings_do_not_mutate_partial_project(self):
        for setting in ("project_name", "tech_stack", "agents_md_custom", "enable_agents",
                        "enable_br", "enable_claude", "enable_ubsignore"):
            with self.subTest(setting=setting):
                result = self.run_shell(f'''
                    if run_creation; then exit 91; fi
                    before=$(wc -l < "$EVENTS")
                    values[{setting}]=changed
                    if run_creation; then exit 92; fi
                    [[ "$(wc -l < "$EVENTS")" == "$before" ]]
                ''')
                self.assert_success(result)
                self.assertIn("different settings", result.stderr)

    def test_restoring_original_settings_allows_retry(self):
        result = self.run_shell('''
            if run_creation; then exit 91; fi
            values[tech_stack]=rust
            if run_creation; then exit 92; fi
            values[tech_stack]=python
            FAIL_STEP=''
            run_creation
        ''')
        self.assert_success(result)
        self.assertTrue((self.project / "AGENTS.md").is_file())

    def test_different_directory_does_not_remove_original(self):
        result = self.run_shell('''
            if run_creation; then exit 91; fi
            values[project_dir]="$PROJECT-other"
            FAIL_STEP=''
            run_creation
        ''')
        self.assert_success(result)
        self.assertTrue((self.project / "README.md").is_file())
        self.assertTrue(Path(str(self.project) + "-other", "AGENTS.md").is_file())

    def test_optional_skip_is_not_replayed_on_later_retry(self):
        result = self.run_shell('''
            try_br_init() { return 2; }
            FAIL_STEP=create_claude
            if run_creation; then exit 91; fi
            [[ "${STEP_STATUS[init_br]}" == skipped ]]
            FAIL_STEP=''
            run_creation
        ''')
        self.assert_success(result)
        self.assertEqual(self.events_read().count("init_br"), 1)

    def test_policy_generator_failure_is_not_written_as_success(self):
        result = self.run_shell('''
            FAIL_STEP=''
            generate_agents_md() { printf 'partial policy'; return 7; }
            if run_creation; then exit 91; fi
            [[ "${STEP_STATUS[create_agents]}" == error ]]
        ''')
        self.assert_success(result)
        self.assertFalse((self.project / "AGENTS.md").exists())

    def test_unknown_step_is_an_error(self):
        result = self.run_shell('''
            if original_execute_step unknown_step; then exit 91; fi
            [[ "${STEP_STATUS[unknown_step]}" == error ]]
        ''')
        self.assert_success(result)

    def test_finalize_never_stages_or_commits_user_work(self):
        result = self.run_shell('''
            FAIL_STEP=''
            git() { echo GIT >> "$EVENTS"; return 0; }
            run_creation
        ''')
        self.assert_success(result)
        self.assertNotIn("GIT", self.events_read())

    def test_errexit_does_not_activate_legacy_cleanup(self):
        result = self.run_shell('run_creation')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.project / "README.md").exists())
        self.assertNotIn("CLEANUP", self.events_read())

    def test_menu_retry_preserves_state_and_navigation_stdout(self):
        result = self.run_shell('''
            handle_progress_input
            FAIL_STEP=''
            handle_progress_input
        ''', "r")
        self.assert_success(result)
        self.assertEqual(result.stdout, "success\n")
        self.assertEqual(self.events_read().count("create_readme"), 1)

    def test_menu_back_and_quit_do_not_rollback(self):
        for key, code in (("b", 1), ("q", 2), ("\x1b", 2), ("", 2)):
            with self.subTest(key=key):
                result = self.run_shell(f'''
                    result=0
                    handle_progress_input || result=$?
                    [[ "$result" == {code} ]]
                ''', key)
                self.assert_success(result)
                self.assertEqual(result.stdout, "")

    def test_request_serialization_is_unambiguous_and_inert(self):
        result = self.run_shell(r'''
            values[agents_md_custom]=$'a\nb\n$(touch INJECTED)'
            first=$(creation_request)
            values[agents_md_custom]='a b $(touch INJECTED)'
            second=$(creation_request)
            [[ "$first" != "$second" && ! -e INJECTED ]]
        ''')
        self.assert_success(result)

if __name__ == "__main__":
    unittest.main(verbosity=2)
