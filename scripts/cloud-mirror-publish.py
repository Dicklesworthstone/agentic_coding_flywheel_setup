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
from urllib.parse import urlsplit
import zipfile

KEY = "RWTQGPeLsnm9G7VFdFWkkcRi3wJK/PqsYxWC+oLNN74W9IjBxRU1Xu70"
FALLBACK_REPO = "Dicklesworthstone/agentic_coding_flywheel_setup"
FALLBACK_TAG = "cloud-binaries-v1"
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
    "jfp": ("Dicklesworthstone/jeffreysprompts.com", "jfp-linux-x64-baseline", ["jfp"], None),
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
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", version):
            raise ValueError("Unsafe release tag")
        checksums = fetch(relay + "/" + version + "/SHA256SUMS")
        rows = [row.split() for row in checksums.decode().splitlines() if row.strip()]
        matched = [row[0] for row in rows if len(row) == 2 and row[1].lstrip('*').removeprefix('./') == pattern]
        if len(matched) != 1 or not re.fullmatch(r"[a-f0-9]{64}", matched[0]):
            raise ValueError("JSM relay checksum missing, malformed or duplicated")
        sha = matched[0]
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
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", version):
        raise ValueError("Unsafe release tag")
    assets = {item["name"]: item for item in release["assets"]}
    name = pattern.format(v=version.removeprefix("v"))
    if name not in assets:
        raise ValueError(f"{tool}: missing required release asset: {name}")
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


def publish_jsm_fallback(entry, stage):
    """Copy the verified vendor archive to an immutable anonymous GitHub URL."""
    source = entry["source"]
    version, sha = entry["version"], source["sha256"]
    if (not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", version)
            or not re.fullmatch(r"[a-f0-9]{64}", sha)
            or source["asset"] != TOOLS["jsm"][1]):
        raise ValueError("Invalid JSM fallback artifact identity")
    data = (stage / "jsm" / version / source["asset"]).read_bytes()
    if not hmac.compare_digest(digest(data), sha):
        raise ValueError("JSM fallback staging checksum mismatch")
    name = f"jsm-{version}-linux-x86_64-{sha}.tar.gz"
    public_dir = stage / "public-assets"
    public_dir.mkdir(exist_ok=True)
    asset = public_dir / name
    if asset.exists():
        if not hmac.compare_digest(digest(asset.read_bytes()), sha):
            raise ValueError("JSM fallback local asset collision")
    else:
        with asset.open("xb") as output:
            output.write(data)
    endpoint = f"repos/{FALLBACK_REPO}/releases/tags/{FALLBACK_TAG}"
    try:
        release = json.loads(run("gh", "api", endpoint))
    except subprocess.CalledProcessError as error:
        # Only an actual missing release permits creation, never an auth,
        # rate-limit or transport failure. Preserve all other diagnostics.
        if str(json.loads(error.output or "{}").get("status")) != "404":
            raise
        release = None
    if release is None:
        run("gh", "release", "create", FALLBACK_TAG, str(asset), "--repo", FALLBACK_REPO,
            "--target", "main", "--prerelease", "--latest=false",
            "--title", "Verified cloud CLI binaries",
            "--notes", "Public copies of vendor-verified CLI archives for restricted cloud environments. "
            "The cloud-mirror.json manifest pins each artifact by SHA256 and retains its upstream provenance. "
            "Assets are content addressed and never replaced. This is not the latest ACFS software release.")
        release = json.loads(run("gh", "api", endpoint))
    if release.get("draft", True) or release.get("tag_name") != FALLBACK_TAG:
        raise ValueError("JSM fallback release is not public or has the wrong tag")
    matches = [item for item in release["assets"] if item["name"] == name]
    if not matches:
        # No --clobber: even a concurrent publisher cannot replace a version.
        run("gh", "release", "upload", FALLBACK_TAG, str(asset), "--repo", FALLBACK_REPO)
        release = json.loads(run("gh", "api", endpoint))
        matches = [item for item in release["assets"] if item["name"] == name]
    if len(matches) != 1 or matches[0].get("digest") != "sha256:" + sha:
        raise ValueError("JSM fallback GitHub asset digest mismatch/missing")
    url = f"https://github.com/{FALLBACK_REPO}/releases/download/{FALLBACK_TAG}/{name}"
    if not hmac.compare_digest(digest(fetch(url)), sha):
        raise ValueError("JSM fallback anonymous readback checksum mismatch")
    # Keep provenance distinct from the public distribution location. The
    # installer authenticates both the mirror and fallback with pinned hashes.
    source["upstream_url"] = source.get("upstream_url", source["url"])
    source["url"] = url
    print("jsm: public GitHub fallback hash verified", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="New candidate manifest; never overwrites")
    parser.add_argument("--base-url", default="https://downloads.agent-flywheel.com/acfs-cloud/v1")
    parser.add_argument("--bucket", default="acfs-cloud-tools")
    parser.add_argument("--publish", action="store_true")
    parser.add_argument("--tools", nargs="+", choices=TOOLS, default=list(TOOLS),
                        help="Refresh these tools, retaining other entries from cloud-mirror.json")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Choose a new output path; candidate already exists")
    if len(set(args.tools)) != len(args.tools):
        parser.error("Each tool may be selected only once")
    if not re.fullmatch(r"https://[A-Za-z0-9.-]+(?::[0-9]+)?(?:/[A-Za-z0-9_.-]+)*", args.base_url):
        parser.error("Choose an HTTPS base URL without query, fragment or trailing slash")
    object_prefix = urlsplit(args.base_url).path.strip("/")
    if any(part in (".", "..") for part in object_prefix.split("/")):
        parser.error("Unsafe base URL path")
    retained = {}
    if set(args.tools) != set(TOOLS):
        try:
            current = json.loads((Path(__file__).resolve().parents[1] / "cloud-mirror.json").read_text())
        except (OSError, json.JSONDecodeError) as error:
            parser.error(f"Cannot retain the existing manifest: {error}")
        if current.get("schema") != 1 or current.get("platform") != "linux-x86_64" or current.get("base_url") != args.base_url:
            parser.error("A partial refresh must use the current manifest's platform and base URL")
        retained = {tool: entry for tool, entry in current["tools"].items() if tool not in args.tools}
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
                error.close()
            else:
                if not hmac.compare_digest(digest(existing), entry["sha256"]):
                    raise ValueError(f"Remote object mismatch: {tool}; refusing overwrite")
                continue
            object_key = "/".join(part for part in (args.bucket, object_prefix, entry["file"]) if part)
            run("wrangler", "r2", "object", "put", object_key,
                "--file", str(args.stage / entry["file"]), "--remote", "--content-type", "application/gzip",
                "--cache-control", "public, max-age=31536000, immutable")
            if not hmac.compare_digest(digest(fetch(url)), entry["sha256"]):
                raise ValueError(f"Public readback mismatch: {tool}")
            print(f"{tool}: published and public hash verified", flush=True)
        if "jsm" in entries:
            publish_jsm_fallback(entries["jsm"], args.stage)
    manifest = {"schema": 1, "platform": "linux-x86_64", "base_url": args.base_url, "tools": {**retained, **entries}}
    with args.output.open("x") as output:
        json.dump(manifest, output, indent=2, sort_keys=True)
        output.write("\n")


if __name__ == "__main__":
    main()
