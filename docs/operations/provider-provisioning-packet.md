# Provider Provisioning Packet Design

This note records the `bd-eyx13` v1 contract for provider-agnostic VPS
provisioning packets. It is a schema and lifecycle contract for later provider
implementations; it does not perform hosted provisioning by itself.

## Purpose

ACFS currently guides beginners through provider choice, VPS sizing, SSH setup,
installer command generation, and support-bundle collection. Provider-specific
automation needs a stable handoff format before any hosted or API-driven
execution is added.

The provisioning packet answers:

> What should be provisioned, how should ACFS be bootstrapped on it, and which
> metadata can support safely inspect without provider secrets?

The packet must remain portable across providers. It must never require storing
provider API credentials, checkout session cookies, private SSH keys, raw host
addresses, passwords, or payment details.

## Source Surfaces

The v1 packet is designed to line up with the existing web and support surfaces:

| Source | Existing file | Packet section |
| --- | --- | --- |
| Provider and plan table | `apps/web/lib/vpsProviders.ts` | `provider`, `region`, `size`, `osImage` |
| Readiness checks | `validateVPSReadiness` | `compatibility.readinessStatus`, `compatibility.readinessChecks` |
| Capacity model | `calculateRequiredSpecs`, `evaluatePlan` | `compatibility.requiredSpecs`, selected plan status |
| Wizard install command | `apps/web/lib/commandBuilder.ts` | `install.command`, verification commands |
| Support bundle redaction | `scripts/lib/support.sh` | `privacy`, support-safe projection rules |

## Non-Goals

- No provider API calls in the schema bead.
- No hosted checkout, payment, account creation, or credential storage.
- No raw target host address in the support-safe projection.
- No private SSH key material or private-key path in the packet.
- No automatic Beads, Agent Mail, NTM, RU, or RCH mutation.
- No cloud provider lock-in; provider adapters must target the same shape.

## Canonical Type Contract

The importable v1 TypeScript contract lives in:

```text
apps/web/lib/providerProvisioningPacket.ts
```

The schema id is:

```text
acfs.provider-provisioning-packet.v1
```

Required top-level sections:

| Section | Purpose |
| --- | --- |
| `schema`, `schemaVersion` | Breaking-change boundary. |
| `stage` | Lifecycle status such as `draft`, `installer_ready`, or `verified`. |
| `privacy` | Redaction and support-bundle safety contract. |
| `provenance` | Where the packet came from and which ACFS data models were used. |
| `provider` | Provider identity, product URL, automation level, and manual steps. |
| `region` | Provider region id/label and readiness status. |
| `size` | Plan name, RAM, vCPU, storage, and optional price. |
| `osImage` | Ubuntu version, minimum/preferred versions, and optional provider image id. |
| `access` | Target username and public SSH key metadata. |
| `cloudInit` | Whether user-data is used, plus hash/template metadata. |
| `install` | Exact ACFS installer command, mode, ref, and module selection. |
| `compatibility` | Workload, target agent count, specs, readiness, and capacity status. |
| `verificationCommands` | Commands expected before marking the packet verified. |
| `expectedArtifacts` | Provider, installer, and support artifacts to expect. |

## Lifecycle

| Stage | Meaning | Allowed actor |
| --- | --- | --- |
| `draft` | Wizard has enough intent to describe the desired VPS. | Web wizard |
| `ready_for_manual_provider_checkout` | Operator can follow provider console steps. | Web wizard |
| `ready_for_api_provisioning` | Future adapter has enough non-secret intent to call a provider API. | Provider adapter |
| `provider_server_created` | A VPS exists, but ACFS install has not been verified. | Operator or adapter |
| `installer_ready` | SSH/cloud-init path is ready for the exact install command. | Operator or adapter |
| `verified` | ACFS doctor and support-bundle checks completed. | Installer or operator |
| `blocked` | Readiness, capacity, provider, or artifact checks failed. | Any actor |

State transitions must be append-only in future audit logs. A later
implementation may write events, but the packet itself should remain a current
state snapshot.

## Required Intent Fields

Provider implementations must be able to read the same core intent regardless
of provider:

```json
{
  "provider": {
    "id": "contabo",
    "name": "Contabo",
    "productUrl": "https://contabo.com/en-us/vps/",
    "automationLevel": "manual",
    "manualCheckoutRequired": true
  },
  "region": {
    "id": "us",
    "label": "US",
    "readinessStatus": "supported"
  },
  "size": {
    "planName": "Cloud VPS 50",
    "ramGB": 64,
    "vCPU": 16,
    "storageGB": 400,
    "priceUSD": 56
  },
  "osImage": {
    "distribution": "ubuntu",
    "version": "25.10",
    "minimumVersion": "22.04",
    "preferredVersions": ["25.10", "24.04"],
    "readinessStatus": "supported"
  }
}
```

The packet may include a provider-specific image id or region code when known,
but provider adapters must not require those fields for manual providers.

## SSH And Cloud-Init Rules

`access` may include:

- target Linux username
- root-login expectation
- public SSH key label
- public SSH key fingerprint
- public SSH key material when the user explicitly generated or pasted a public
  key

`access` must not include:

- private SSH key material
- private SSH key path
- provider account password
- provider API token

`cloudInit` may describe one of four modes:

| Mode | Meaning |
| --- | --- |
| `none` | Operator will run the installer manually over SSH. |
| `manual_paste` | Operator can paste generated user-data into provider UI. |
| `provider_user_data` | Provider console stores user-data as part of manual creation. |
| `api_user_data` | Future adapter can send user-data through a provider API. |

Support bundles may include `cloudInit.userDataSha256`, `cloudInit.templateRef`,
and a redacted preview. They must not include raw rendered user-data.

## Install And Verification

The packet keeps the exact install command because retrying or auditing ACFS
setup requires copy-paste fidelity:

```json
{
  "install": {
    "mode": "vibe",
    "sourceRef": "main",
    "command": "curl -fsSL \"https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh\" | bash -s -- --yes --mode vibe",
    "commandRunLocation": "vps-root-shell"
  }
}
```

The base verification commands are:

| Id | Run on | Support-safe | Purpose |
| --- | --- | --- | --- |
| `ssh-root` | local | no | Confirms the new VPS is reachable. |
| `installer` | VPS | yes | Confirms the exact installer command ran. |
| `doctor` | VPS | yes | Confirms `acfs doctor` health. |
| `support-bundle` | VPS | yes | Confirms redacted diagnostics can be produced. |

Provider adapters may add provider-specific checks, but they must not remove
the base checks.

## Support-Bundle Projection

Support bundles may include a redacted packet metadata projection. That
projection may include:

- schema id and version
- stage
- provider id/name/automation level
- region id and readiness status
- plan name, RAM, vCPU, and storage
- Ubuntu version
- target username
- public SSH key label/fingerprint
- cloud-init mode and user-data hash
- install mode/source ref
- workload, target agent count, capacity status, readiness status
- verification command ids
- expected artifact ids and path patterns

It must not include:

- raw target host address
- raw hostnames or IP addresses
- provider account ids, order ids, project ids, or dashboard sessions
- API keys, tokens, passwords, cookies, credentials, or secrets
- private SSH key material or private-key paths
- raw cloud-init/user-data payloads
- environment variables used to run the installer
- local operator paths

The TypeScript contract exposes `PROVIDER_PACKET_FORBIDDEN_FIELD_NAMES`,
`PROVIDER_PACKET_REDACTED_FIELD_PATHS`, and
`PROVIDER_PACKET_SUPPORT_BUNDLE_SAFE_PATHS` so later support-bundle code can
test against the same policy.

## Compatibility With Current Provider Guidance

The packet reuses the current readiness and capacity vocabulary:

- provider status: `supported`, `borderline`, `unsupported`, `unknown`
- plan status: `pass`, `warn`, `fail`
- workload id: `light`, `standard`, `heavy`
- required specs from `calculateRequiredSpecs`
- selected-plan capacity from `evaluatePlan`
- readiness checks from `validateVPSReadiness`

This keeps provider packet generation aligned with the existing rent-VPS wizard
and avoids introducing a second sizing model.

## Manual Provider Boundaries

The current wizard providers remain manual in v1.

### Contabo

- Choose the ACFS-recommended VPS product in the provider console.
- Select region and Ubuntu image manually.
- Paste or select the public SSH key manually.
- Complete checkout and payment manually.
- Copy the assigned host address into the wizard or password manager; keep it
  out of support-safe packet metadata.

### OVH

- Choose the ACFS-recommended VPS product in the provider console.
- Select region and Ubuntu image manually.
- Attach the public SSH key or use the provider password flow until ACFS
  installs keys.
- Complete checkout and payment manually.
- Copy the assigned host address into the wizard or password manager; keep it
  out of support-safe packet metadata.

### Other Providers

- Verify Ubuntu support, SSH access, RAM, vCPU, and NVMe storage manually.
- Complete account, checkout, and payment steps manually.
- Keep the assigned host address outside support-safe packet metadata.

## Failure And Blocked States

Provider packet consumers should set `stage: "blocked"` when any of these are
true:

- provider is unknown and the operator has not accepted manual verification
- selected plan is undersized
- Ubuntu image is below the ACFS minimum
- region is unsupported by the provider adapter
- SSH public key metadata is missing before provisioning
- exact installer command cannot be built
- redaction policy would include a forbidden field in support output

Failures should include deterministic verification command ids and artifact ids
rather than raw provider errors that may contain private account details.

## CLI Validator

`acfs provisioning-packet --file <packet.json>` validates a packet without
contacting a provider API. It renders human-readable output by default and
emits machine-readable checks with `--json`.

The validator checks:

- schema id and version
- required provider, region, OS, access, install, compatibility, verification,
  and artifact fields
- support-safe redaction flags and forbidden sensitive fields
- provider readiness, Ubuntu image readiness, username format, SSH private-key
  exclusion, and install command/source-ref coherence
- secret-looking scalar values, including raw private keys, common API tokens,
  and raw IPv4 addresses

Unknown providers are valid but return a warning so support can continue with
manual verification. Unsupported readiness or redaction failures return a failed
check.

## Test Plan

The v1 schema bead adds focused web-unit coverage for:

- stable schema id and version
- required field paths for provider, region, size, OS image, SSH, cloud-init,
  install command, verification commands, artifacts, provenance, and redaction
- support-bundle safe paths excluding raw host, private-key, token, password,
  and raw user-data fields
- base verification command ids
- expected artifact ids and redaction requirements
- manual remaining steps for each current wizard provider

The CLI validator bead adds Bash fixture coverage for valid packets, malformed
JSON, redaction refusal, unknown providers, unsupported OS choices, and stable
human/JSON output. Future implementation beads should add support-bundle
projection coverage once that projection exists.
