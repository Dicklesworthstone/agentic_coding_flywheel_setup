#!/usr/bin/env python3
"""Brenner Bot must not replace the ntm, cass and cm that ACFS installs itself.

brenner_bot's install.sh installs its own pinned toolchain (ntm, cass, cm from
its specs/toolchain.manifest.json) into the same bin directory unless told to
skip each one. ACFS installs and updates those tools through their own modules,
so every path that runs the brenner installer must pass all three skip flags.
`acfs update` has done so since GH #210; the install paths must agree with it.
"""
from pathlib import Path
import re
import shlex
import unittest

ROOT = Path(__file__).resolve().parents[2]
REQUIRED = {"--skip-ntm", "--skip-cass", "--skip-cm"}


def manifest_args():
    text = (ROOT / "acfs.manifest.yaml").read_text()
    module = text.split("\n  - id: stack.brenner_bot\n", 1)[1].split("\n  - id: ", 1)[0]
    match = re.search(r"^    verified_installer:\n(?:      .*\n)*?      args: \[(.*)\]$", module, re.M)
    if not match:
        raise AssertionError("stack.brenner_bot verified_installer args not found; update extraction explicitly")
    return [item.strip().strip('"') for item in match.group(1).split(",")]


def generated_args():
    text = (ROOT / "scripts/generated/install_stack.sh").read_text()
    body = text.split("\nacfs_generated_install_stack_brenner_bot() {\n", 1)[1].split("\n}\n", 1)[0]
    calls = re.findall(r"run_as_target_runner 'bash' \"\$verified_installer_file\"(.*?); then", body)
    if len(calls) != 1:
        raise AssertionError(f"expected one brenner installer call in install_stack.sh, found {len(calls)}")
    return shlex.split(calls[0])


def install_sh_args():
    calls = re.findall(
        r'acfs_run_verified_upstream_script_as_target "brenner_bot" "bash"(.*?) \|\|',
        (ROOT / "install.sh").read_text(),
    )
    if len(calls) != 1:
        raise AssertionError(f"expected one brenner installer call in install.sh, found {len(calls)}")
    return shlex.split(calls[0])


def update_sh_args():
    calls = re.findall(
        r"update_run_verified_installer brenner_bot(.*)$",
        (ROOT / "scripts/lib/update.sh").read_text(),
        re.M,
    )
    if len(calls) != 1:
        raise AssertionError(f"expected one brenner installer call in update.sh, found {len(calls)}")
    return shlex.split(calls[0])


class BrennerToolchainSkipTests(unittest.TestCase):
    def assert_skips_toolchain(self, label, args):
        missing = REQUIRED - set(args)
        self.assertFalse(missing, f"{label} runs brenner's installer without {sorted(missing)}: {args}")

    def test_manifest_skips_brenner_toolchain(self):
        self.assert_skips_toolchain("acfs.manifest.yaml stack.brenner_bot", manifest_args())

    def test_generated_stack_installer_skips_brenner_toolchain(self):
        self.assert_skips_toolchain("scripts/generated/install_stack.sh", generated_args())

    def test_install_sh_skips_brenner_toolchain(self):
        self.assert_skips_toolchain("install.sh", install_sh_args())

    def test_update_skips_brenner_toolchain(self):
        self.assert_skips_toolchain("scripts/lib/update.sh", update_sh_args())

    def test_install_and_update_pass_the_same_flags(self):
        flags = lambda args: sorted(a for a in args if a.startswith("--skip-"))
        expected = flags(update_sh_args())
        self.assertEqual(flags(install_sh_args()), expected)
        self.assertEqual(flags(generated_args()), expected)


if __name__ == "__main__":
    unittest.main()
