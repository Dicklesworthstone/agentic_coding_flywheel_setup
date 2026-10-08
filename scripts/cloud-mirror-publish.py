#!/usr/bin/env python3
"""Package verified upstream Linux releases for the public ACFS cloud mirror.

No builds, installers, credentials in output, or implicit git operations. Staging
is retained. Review the candidate manifest, run Linux smoke tests, then commit it.
"""
import argparse
import concurrent.futures
import gzip
import hashlib
import hmac
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import time
import urllib.error
import urllib.request
import zipfile

KEY = "RWTQGPeLsnm9G7VFdFWkkcRi3wJK/PqsYxWC+oLNN74W9IjBxRU1Xu70"
TOOLS = {
    "br": ("Dicklesworthstone/beads_rust", "br-{v}-linux_musl_amd64.tar.gz", ["br"], "RWTQoKUb0Ue4NsqTpPWnABCrIU0+m25zsMlbv6UcRClQ7jmRP3A7NmTB"),
    "bv": ("Dicklesworthstone/beads_viewer", "bv_{v}_linux_amd64.tar.gz", ["bv"], None),
    "am": ("Dicklesworthstone/mcp_agent_mail_rust", "mcp-agent-mail-x86_64-unknown-linux-musl.tar.xz", ["am", "mcp-agent-mail"], KEY),
    "cass": ("Dicklesworthstone/coding_agent_session_search", "cass-linux-amd64.tar.gz", ["cass"], None),
    "cm": ("Dicklesworthstone/cass_memory_system", "cass-memory-linux-x64", ["cm"], None),
    "ms": ("Dicklesworthstone/meta_skill", "ms-{v}-x86_64-unknown-linux-gnu.tar.gz", ["ms"], KEY),
    "ubs": ("Dicklesworthstone/ultimate_bug_scanner", "ubs", ["ubs"], "RWS+jJ7psytzl3v4znpraY9VWBQrICXBFmT3VwvxpTzbuV2Q/CBTDmVJ"),
    "ast-grep": ("ast-grep/ast-grep", "app-x86_64-unknown-linux-gnu.zip", ["ast-grep"], None),
    "jsm": ("Dicklesworthstone/jeffreys-skills.md", "jsm-x86_64-unknown-linux-musl.tar.gz", ["jsm"], None),
    "jfp": ("Dicklesworthstone/jeffreysprompts.com", "jfp-linux-x64", ["jfp"], None),
}


def run(*args):
    return subprocess.check_output(args, text=True, timeout=300)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fetch(url):
    if not url.startswith("https://"):
        raise ValueError("HTTPS required")
    request = urllib.request.Request(url, headers={"User-Agent": "OpenAI File Downloader, XaiImageApiFetch/1.0", "Accept": "*/*"})
    with urllib.request.urlopen(request, timeout=120) as response:
        if not response.url.startswith("https://"):
            raise ValueError("Insecure redirect")
        return response.read()


def archive_files(data, name):
    """Read regular files without extracting any upstream paths onto disk."""
    files, total = {}, 0

    def add(path, size, read):
        nonlocal total
        if path in files:
            raise ValueError(f"Duplicate upstream archive member: {path}")
        total += size
        if size < 0 or total > 1024 * 1024 * 1024:
            raise ValueError("Upstream archive expands beyond 1 GiB")
        files[path] = read()

    if name.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for item in archive.infolist():
                if not item.is_dir():
                    add(item.filename, item.file_size, lambda item=item: archive.read(item))
    else:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
            for item in archive:
                if item.isfile():
                    add(item.name, item.size, lambda item=item: archive.extractfile(item).read())
    return files


def ubs_helpers(source):
    """Require complete, nonempty release checksum tables before publishing."""
    entries = []
    for table in ("MODULE_CHECKSUMS", "HELPER_CHECKSUMS"):
        body = re.search(r"declare -A " + table + r"=\((.*?)\n\)", source, re.S)
        if not body:
            raise ValueError(f"Missing UBS {table}")
        parsed = re.findall(r"\['?([^'\]]+)'?\]='([a-f0-9]{64})'", body.group(1))
        lines = [line.strip() for line in body.group(1).splitlines() if line.strip() and not line.strip().startswith("#")]
        if not parsed or len(parsed) != len(lines):
            raise ValueError(f"Empty or malformed UBS {table}")
        for path, sha in parsed:
            path = f"ubs-{path}.sh" if table == "MODULE_CHECKSUMS" else path
            if PurePosixPath(path).is_absolute() or ".." in PurePosixPath(path).parts:
                raise ValueError(f"Unsafe UBS helper path: {path}")
            if any(existing == path for existing, _ in entries):
                raise ValueError(f"Duplicate UBS helper: {path}")
            entries.append((path, sha))
    return entries


def bundle(files):
    """Deterministic overlay with normalized metadata and no links."""
    out = io.BytesIO()
    with gzip.GzipFile(fileobj=out, mode="wb", filename="", mtime=0, compresslevel=1) as gz:
        with tarfile.open(fileobj=gz, mode="w") as archive:
            for name, data in sorted(files.items()):
                path = PurePosixPath(name)
                if path.is_absolute() or ".." in path.parts or path.parts[0] not in ("bin", "share"):
                    raise ValueError(f"Unsafe bundle member: {name}")
                info = tarfile.TarInfo(name)
                info.size, info.mode, info.mtime = len(data), 0o755 if name.startswith("bin/") or name.endswith(".sh") else 0o644, 0
                archive.addfile(info, io.BytesIO(data))
    return out.getvalue()


def prepare(tool, stage):
    repo, pattern, bins, key = TOOLS[tool]
    if tool == "jsm":
        # The vendor's public relay serves this private repository's releases.
        relay = "https://jeffreys-skills.md/api/v1/downloads/jsm"
        version = fetch(relay + "/latest.txt").decode().strip()
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", version):
            raise ValueError("Unsafe release tag")
        checksums = fetch(relay + "/" + version + "/SHA256SUMS")
        sha = next(row.split()[0] for row in checksums.decode().splitlines() if row.split()[-1] == pattern)
        release = {"tag_name": version, "assets": [
            {"name": pattern, "digest": "sha256:" + sha, "browser_download_url": f"{relay}/{version}/{pattern}"},
            {"name": "SHA256SUMS", "digest": "sha256:" + digest(checksums), "browser_download_url": f"{relay}/{version}/SHA256SUMS"},
        ]}
    else:
        try:
            release = json.loads(run("gh", "api", f"repos/{repo}/releases/latest"))
        except json.JSONDecodeError as error:
            raise ValueError(f"{repo}: gh returned invalid release metadata") from error
    version = release["tag_name"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", version):
        raise ValueError("Unsafe release tag")
    assets = {item["name"]: item for item in release["assets"]}
    name = pattern.format(v=version.removeprefix("v"))
    work = stage / tool / version
    work.mkdir(parents=True, exist_ok=True)

    def asset(filename):
        meta = assets[filename]
        dest = work / filename
        data = dest.read_bytes() if dest.exists() else fetch(meta["browser_download_url"])
        expected = meta.get("digest", "")
        if not hmac.compare_digest(expected, "sha256:" + digest(data)):
            raise ValueError(f"{tool}: GitHub asset digest mismatch/missing for {filename}")
        if not dest.exists():
            dest.write_bytes(data)
        return data

    data = asset(name)
    # Prefer the release's per-file checksum; otherwise use its checksum list.
    sums_name = next((n for n in (name + ".sha256", "SHA256SUMS", "checksums.txt", "checksums.sha256") if n in assets), None)
    if sums_name:
        sums = asset(sums_name).decode()
        rows = [line.split() for line in sums.splitlines() if line.strip()]
        matched = [row[0] for row in rows if len(row) > 1 and row[-1].lstrip("*").removeprefix("./") == name]
        if len(rows) == 1 and len(rows[0]) == 1 and sums_name == name + ".sha256":
            matched = [rows[0][0]]
        if matched != [digest(data)]:
            raise ValueError(f"{tool}: upstream checksum mismatch for {name}")
    elif tool != "ast-grep":
        raise ValueError(f"{tool}: missing upstream checksum")

    signed = None
    signs_archive = name + ".minisig" in assets
    if signs_archive:
        signed = name
    elif "SHA256SUMS.minisig" in assets:
        signed = "SHA256SUMS"
    if key and not signed:
        raise ValueError(f"{tool}: expected release signature is missing")
    if signed:
        if not key:
            raise ValueError(f"{tool}: review and pin the new signing key")
        asset(signed)
        asset(signed + ".minisig")
        run("minisign", "-Vm", str(work / signed), "-x", str(work / (signed + ".minisig")), "-P", key)
        if not signs_archive and not any(line.split() == [digest(data), name] or line.split() == [digest(data), "*" + name] for line in (work / signed).read_text().splitlines()):
            raise ValueError(f"{tool}: signed checksums do not cover artifact")

    files = {}
    if name.endswith((".tar.gz", ".tar.xz", ".zip")):
        contents = archive_files(data, name)
        for binary in bins:
            matches = [value for path, value in contents.items() if PurePosixPath(path).name == binary]
            if len(matches) != 1:
                raise ValueError(f"{tool}: expected exactly one {binary}, got {len(matches)}")
            files["bin/" + binary] = matches[0]
    else:
        files["bin/" + bins[0]] = data

    if tool == "ubs":
        # UBS is an interpreted program. Bundle every module/helper from its
        # release-pinned, hash-checked tables; never run its system installer.
        entries = ubs_helpers(data.decode())

        def helper(entry):
            path, sha = entry
            content = fetch(f"https://raw.githubusercontent.com/{repo}/{version}/modules/{path}")
            if not hmac.compare_digest(digest(content), sha):
                raise ValueError(f"UBS helper mismatch: {path}")
            return "share/ubs/modules/" + path, content

        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
            files.update(pool.map(helper, entries))

    packed = bundle(files)
    sha = digest(packed)
    # Content addressing permits repackaging a version without mutating old URLs.
    relative = f"{tool}/{version}/{sha}/{tool}-linux-x86_64.tar.gz"
    target = stage / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.read_bytes() != packed:
        raise ValueError("Existing content-addressed bundle differs")
    if not target.exists():
        target.write_bytes(packed)
    print(f"{tool}: {version}, {len(packed):,} bytes, verified", flush=True)
    return tool, {"version": version, "file": relative, "sha256": sha, "bins": bins,
                  "source": {"repo": repo, "tag": version, "asset": name, "url": assets[name]["browser_download_url"], "sha256": digest(data),
                             "verification": "minisign+sha256" if signed else "sha256"}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="New candidate manifest; never overwrites")
    parser.add_argument("--base-url", default="https://downloads.agent-flywheel.com/acfs-cloud/v1")
    parser.add_argument("--bucket", default="acfs-cloud-tools")
    parser.add_argument("--publish", action="store_true")
    parser.add_argument("--tools", nargs="+", choices=TOOLS, default=list(TOOLS))
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Choose a new output path; candidate already exists")
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        entries = dict(pool.map(lambda tool: prepare(tool, args.stage), args.tools))
    if args.publish:
        for tool, entry in entries.items():
            url = args.base_url.rstrip("/") + "/" + entry["file"]
            try:
                # Do not cache a negative lookup at the eventual public URL.
                existing = fetch(url + "?existence=" + str(time.time_ns()))
            except urllib.error.HTTPError as error:
                if error.code != 404:
                    raise
            else:
                if not hmac.compare_digest(digest(existing), entry["sha256"]):
                    raise ValueError(f"Remote object mismatch: {tool}; refusing overwrite")
                continue
            run("wrangler", "r2", "object", "put", args.bucket + "/acfs-cloud/v1/" + entry["file"],
                "--file", str(args.stage / entry["file"]), "--remote", "--content-type", "application/gzip",
                "--cache-control", "public, max-age=31536000, immutable")
            if not hmac.compare_digest(digest(fetch(url)), entry["sha256"]):
                raise ValueError(f"Public readback mismatch: {tool}")
            print(f"{tool}: published and public hash verified", flush=True)
    manifest = {"schema": 1, "platform": "linux-x86_64", "base_url": args.base_url, "tools": entries}
    with args.output.open("x") as output:
        json.dump(manifest, output, indent=2, sort_keys=True)
        output.write("\n")


if __name__ == "__main__":
    main()
