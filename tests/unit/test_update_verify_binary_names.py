"""The command `acfs update` smoke-checks after a verified installer must be the command the manifest says
that module provides.

update_verify_tool_or_rollback() treats a zero-exit install that publishes no `<binary>` as a failed install.
When update_tool_rollback_binary_name() falls through to the checksum key for a module whose binary has a
different name, every update reports "POST-INSTALL VERIFICATION FAILED for <tool> at : binary missing" even
though the install worked (fleet 2026-11-25: SRPS installs `sysmoni`, TRU installs `toon`; mcp_agent_mail's
`am` was masked only by an acfs hold).
"""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = (ROOT / "acfs.manifest.yaml").read_text()
UPDATE_SH = (ROOT / "scripts/lib/update.sh").read_text()


def manifest_modules():
    """(id, verified_installer tool, set of commands the manifest says the module provides)."""
    blocks = re.split(r"(?m)^  - id: ", MANIFEST)[1:]
    for block in blocks:
        module_id = block.split("\n", 1)[0].strip()
        tool = re.search(r"(?m)^    verified_installer:\n(?:      .*\n)*?      tool: ([A-Za-z0-9_.-]+)", block)
        if not tool:
            continue
        provides = set(re.findall(r'(?m)^      cli_name: "?([A-Za-z0-9_.-]+)"?', block))
        check = re.search(r'(?m)^    installed_check:\n(?:      .*\n)*?      command: "(.*)"', block)
        if check:
            provides.update(re.findall(r"command -v ([A-Za-z0-9_.-]+)", check.group(1)))
        yield module_id, tool.group(1), provides


TOOL_KEY = re.compile(r"[A-Za-z0-9_.-]+")


def rollback_binary_name(tool):
    # Runs only the one case-statement function, taken from update.sh; the key is passed as "$1", never spliced
    # into the script text, and must look like a manifest checksum key.
    if not TOOL_KEY.fullmatch(tool):
        raise ValueError(f"not a tool key: {tool!r}")
    fn = re.search(r"(?ms)^update_tool_rollback_binary_name\(\) \{.*?^\}", UPDATE_SH).group(0)
    out = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-c", fn + '\nupdate_tool_rollback_binary_name "$1"', "_", tool],
                         capture_output=True, text=True, check=True, timeout=10)
    return out.stdout.strip()


class UpdateVerifyBinaryNamesTests(unittest.TestCase):
    def test_manifest_has_verified_installer_modules(self):
        ids = {m for m, _, _ in manifest_modules()}
        self.assertGreater(len(ids), 30)
        self.assertTrue({"stack.srps", "utils.toon_rust", "stack.mcp_agent_mail"} <= ids)

    def test_checked_binary_is_one_the_manifest_says_the_module_provides(self):
        checked = 0
        for module_id, tool, provides in manifest_modules():
            got = rollback_binary_name(tool)
            if not got or not provides:
                continue  # explicit opt-out (nvm, rust) or a module that names no command
            checked += 1
            with self.subTest(module=module_id, tool=tool):
                self.assertIn(got, provides,
                              f"acfs update would smoke-check `{got}` but {module_id} provides {sorted(provides)}")
        self.assertGreater(checked, 30)

    def test_fleet_regressions(self):
        self.assertEqual(rollback_binary_name("srps"), "sysmoni")
        self.assertEqual(rollback_binary_name("tru"), "toon")
        self.assertEqual(rollback_binary_name("mcp_agent_mail"), "am")


if __name__ == "__main__":
    unittest.main()
