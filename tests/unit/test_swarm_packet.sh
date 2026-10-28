#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs swarm packet generator
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWARM_PACKET_SH="$REPO_ROOT/scripts/lib/swarm_packet.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_SWARM_PACKET_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-swarm-packet-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

mkdir -p "$ARTIFACT_DIR"

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    if [[ -n "${2:-}" ]]; then
        echo "  Reason: $2"
    fi
}

write_fixture() {
    local name="$1"
    local path="$ARTIFACT_DIR/$name"
    cat > "$path"
    printf '%s\n' "$path"
}

bead_fixture() {
    write_fixture bead.json <<'JSON'
[
  {
    "id": "bd-n968h",
    "title": "Generate per-agent swarm startup packets from Beads, AGENTS, CASS, and CM",
    "description": "Packet generator fixture",
    "status": "in_progress",
    "priority": 1,
    "issue_type": "feature",
    "labels": ["cass", "cm", "coordination", "swarm"]
  }
]
JSON
}

agents_fixture() {
    write_fixture AGENTS.md <<'EOF'
# AGENTS.md fixture

- Never delete files.
- Use Beads and Agent Mail for coordination.
- Use RCH for CPU-heavy Rust gates.
- Policy examples must be sanitized before packet output:
  git reset --hard
  git clean -fd
  rm -rf
  bv
  bd ready
  cargo test
EOF
}

readme_fixture() {
    write_fixture README.md <<'EOF'
# README fixture

ACFS provides swarm planning, status, doctor, simulation, and startup packet helpers.
EOF
}

cm_fixture() {
    write_fixture cm.json <<'JSON'
{"items":[{"summary":"Prior swarm work kept current repo instructions above memory-derived hints."}]}
JSON
}

cass_fixture() {
    write_fixture cass.json <<'JSON'
{"results":[{"summary":"Recent packet design expected compact prompt material and explicit drift checks."}]}
JSON
}

large_cm_fixture() {
    local path="$ARTIFACT_DIR/large-cm.json"
    {
        printf '{"items":['
        for _ in $(seq 1 200); do
            printf '{"summary":"large bounded context fixture that should be truncated safely"},'
        done
        printf '{"summary":"end"}]}\n'
    } > "$path"
    printf '%s\n' "$path"
}

run_packet_json() {
    local name="$1"
    shift
    local output status

    set +e
    output="$(bash "$SWARM_PACKET_SH" --json "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.json"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

run_packet_markdown() {
    local name="$1"
    shift
    local output status

    set +e
    output="$(bash "$SWARM_PACKET_SH" --markdown "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.md"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

test_json_packet_includes_required_workflow() {
    local bead agents readme cm cass output status
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$(cm_fixture)"
    cass="$(cass_fixture)"

    output="$(run_packet_json full \
        --bead-file "$bead" \
        --agents-file "$agents" \
        --readme-file "$readme" \
        --cm-file "$cm" \
        --cass-file "$cass" \
        --repo "$REPO_ROOT" \
        --agent-name SilentPeak \
        --role implementation \
        --max-chars 9000)"
    status="$(cat "$ARTIFACT_DIR/full.exit")"

    [[ "$status" -eq 0 ]] || return 1
    jq -e '
      .status == "pass" and
      .agent.name == "SilentPeak" and
      .bead.id == "bd-n968h" and
      .context.cm.status == "available" and
      .context.cass.status == "available" and
      .safety.read_only == true and
      .safety.mutates_beads == false and
      .safety.sends_agent_mail == false and
      (.commands.start_checks[] | select(. == "bv --robot-next")) and
      (.commands.start_checks[] | select(. == "bv --robot-triage")) and
      (.commands.agent_mail[] | select(contains("file_reservation_paths"))) and
      (.commands.gates[] | select(. == "rch exec -- cargo test")) and
      (.commands.gates[] | select(. == "ubs $(git diff --name-only --cached)")) and
      (.commands.closeout[] | select(. == "git push origin main:master")) and
      (.packet_markdown | contains("Treat CM and CASS context as stale"))
    ' <<<"$output" >/dev/null || return 1

    pass "json_packet_includes_required_workflow"
}

test_markdown_packet_is_bounded() {
    local bead agents readme cm cass output status
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$(large_cm_fixture)"
    cass="$(cass_fixture)"

    output="$(run_packet_markdown bounded \
        --bead-file "$bead" \
        --agents-file "$agents" \
        --readme-file "$readme" \
        --cm-file "$cm" \
        --cass-file "$cass" \
        --repo "$REPO_ROOT" \
        --agent-name AgentOne \
        --max-chars 4200)"
    status="$(cat "$ARTIFACT_DIR/bounded.exit")"

    [[ "$status" -eq 0 ]] || return 1
    (( ${#output} <= 4200 )) || return 1
    [[ "$output" == *"[truncated:"* ]] || return 1
    [[ "$output" == *"bv --robot-next"* ]] || return 1
    [[ "$output" == *"file_reservation_paths"* ]] || return 1

    pass "markdown_packet_is_bounded"
}

test_missing_cm_and_cass_warn_without_failing() {
    local bead agents readme output status
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"

    output="$(run_packet_json missing_context \
        --bead-file "$bead" \
        --agents-file "$agents" \
        --readme-file "$readme" \
        --repo "$REPO_ROOT" \
        --agent-name AgentTwo \
        --no-live-context)"
    status="$(cat "$ARTIFACT_DIR/missing_context.exit")"

    [[ "$status" -eq 0 ]] || return 1
    jq -e '
      .status == "warn" and
      .context.cm.status == "missing" and
      .context.cass.status == "missing" and
      (.warnings[] | select(contains("cm context unavailable"))) and
      (.warnings[] | select(contains("cass context unavailable")))
    ' <<<"$output" >/dev/null || return 1

    pass "missing_cm_and_cass_warn_without_failing"
}

test_generated_content_lint_blocks_unsafe_templates() {
    local bead agents readme cm cass output status line trimmed
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$(cm_fixture)"
    cass="$(cass_fixture)"

    output="$(run_packet_markdown lint \
        --bead-file "$bead" \
        --agents-file "$agents" \
        --readme-file "$readme" \
        --cm-file "$cm" \
        --cass-file "$cass" \
        --repo "$REPO_ROOT" \
        --agent-name AgentThree \
        --max-chars 9000)"
    status="$(cat "$ARTIFACT_DIR/lint.exit")"

    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" != *"rm -rf"* ]] || return 1
    [[ "$output" != *"git reset --hard"* ]] || return 1
    [[ "$output" != *"git clean -fd"* ]] || return 1

    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        if [[ "$trimmed" == bv* && "$trimmed" != bv\ --robot* ]]; then
            return 1
        fi
        if [[ "$trimmed" == bd\ * ]]; then
            return 1
        fi
        if [[ "$trimmed" == cargo\ * ]]; then
            return 1
        fi
    done <<<"$output"

    pass "generated_content_lint_blocks_unsafe_templates"
}

test_context_service_credentials_are_redacted_before_packet_output() {
    local bead agents readme cm cass output markdown_output secret
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$ARTIFACT_DIR/service-cm.json"
    cass="$ARTIFACT_DIR/service-cass.json"
    # The JSON packet must not bypass its sanitized task brief through bead.source.
    local secret_bead="$ARTIFACT_DIR/service-bead.json"
    jq '.[0].title = "Review AIza0123456789abcdefghijklmnopqrstuvwxy" |
        .[0].description = ("Captured https://hooks." + "slack.com/services/T12345678/B12345678/fixtureBeadWebhook123456") |
        .[0].labels = ["coordination", "tskey-auth-fixtureLabel1234567890"] |
        .[0].acceptance_criteria = "Keep the real acceptance criterion in the delivered task brief"' "$bead" > "$secret_bead"
    bead="$secret_bead"
    cp "$bead" "$bead.before"
    printf '%s\n' '{"message":"AIza0123456789abcdefghijklmnopqrstuvwxy https:\/\/hooks.slack.com\/services\/T12345678\/B12345678\/fixturePacketSlack123456 https://hooks.slack-gov.com/services/T12345678/B12345678/fixturePacketGov123456 `https://discord.com/api/webhooks/123456789012345678/fixturePacketCode123456`"}' > "$cm"
    printf '%s\n' '{"message":"tskey-auth-fixture1234567890 HTTPS://DISCORD.COM/api/webhooks/123456789012345678/fixturePacketDiscord123456 https://canary.discord.com/api/v10/webhooks/123456789012345678/fixturePacketVersioned123456","public":"https://example.com/guide"}' > "$cass"
    cp "$cm" "$cm.before"
    cp "$cass" "$cass.before"
    output="$(run_packet_json service-creds \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 20000)"
    [[ "$(cat "$ARTIFACT_DIR/service-creds.exit")" -eq 0 ]] || return 1
    jq -e '.status == "pass" and
      (.bead.labels | index("coordination")) and
      (.packet_markdown | contains("[google api key redacted]")) and
      (.packet_markdown | contains("[webhook url redacted]")) and
      (.packet_markdown | contains("Captured [webhook url redacted]")) and
      (.packet_markdown | contains("`[webhook url redacted]`")) and
      (.packet_markdown | contains("Keep the real acceptance criterion in the delivered task brief")) and
      (.packet_markdown | contains("https://example.com/guide"))' <<<"$output" >/dev/null || return 1
    markdown_output="$(run_packet_markdown service-creds-markdown \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 20000)"
    [[ "$(cat "$ARTIFACT_DIR/service-creds-markdown.exit")" -eq 0 ]] || return 1
    [[ "$markdown_output" == *"Keep the real acceptance criterion in the delivered task brief"* ]] || return 1
    for secret in AIza0123456789abcdefghijklmnopqrstuvwxy tskey-auth-fixture1234567890 \
        fixturePacketSlack123456 fixturePacketGov123456 \
        fixturePacketDiscord123456 fixturePacketVersioned123456 fixtureBeadWebhook123456 \
        tskey-auth-fixtureLabel1234567890 fixturePacketCode123456; do
        [[ "$output" != *"$secret"* ]] || return 1
        [[ "$markdown_output" != *"$secret"* ]] || return 1
    done
    cmp -s "$bead" "$bead.before" || return 1
    cmp -s "$cm" "$cm.before" || return 1
    cmp -s "$cass" "$cass.before" || return 1
    pass "context_service_credentials_are_redacted_before_packet_output"
}

test_context_credential_aliases_preserve_public_metadata() {
    local bead agents readme cm cass output markdown_output
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$ARTIFACT_DIR/alias-cm.json"
    cass="$ARTIFACT_DIR/alias-cass.txt"
    cat > "$cm" <<'JSON'
{"apiKey":"fixtureAliasApiKey2026","secretKey":"fixtureAliasSecret2026","accessKey":"fixtureAliasAccess2026","privateKey":"fixtureAliasPrivate2026","MYSQL_PWD":"fixtureAliasMysqlFirst fixtureAliasMysqlTail","snippet":"apiKey=\"fixtureAliasEscapedFirst fixtureAliasEscapedTail\"","document":"{\"privateKey\":\"fixtureAliasNested2026\",\"message\":\"MYSQL_PWD=\\\"fixtureAliasNestedMsgFirst fixtureAliasNestedMsgTail\\\"\",\"publicCount\":4}","PWD":"/public/workspace","apiKeyCount":123456789,"privateKeyCount":123456789,"eventId":9007199254740993,"unconfigured":{"apiKey":"","MYSQL_PWD":null,"secretKey":false}}
JSON
    cat > "$cass" <<'TEXT'
apiKey=fixtureAliasShell2026
MYSQL_PWD=fixtureAliasPassword2026
secretKey="fixtureAliasSecretFirst fixtureAliasSecretTail"
accessKey='fixtureAliasAccessFirst fixtureAliasAccessTail'
privateKey = "fixtureAliasPrivateFirst fixtureAliasPrivateTail"
ApiKey = 'fixtureAliasApiFirst fixtureAliasApiTail'
mysql_pwd = "fixtureAliasMysqlFirst fixtureAliasMysqlTail"
apiKey=\"fixtureAliasEscapedFirst fixtureAliasEscapedTail\"
API_KEY='fixtureAliasExistingFirst fixtureAliasExistingTail'
SECRET_KEY="fixtureAliasExistingSecretFirst fixtureAliasExistingSecretTail"
apiKey=\"fixtureAliasNestedFirst \\\"fixtureAliasInnerQuote fixtureAliasNestedTail\"
PWD=/public/workspace
apiKeyCount=123456789
privateKeyCount=123456789
TEXT
    cp "$cm" "$cm.before"
    cp "$cass" "$cass.before"
    output="$(run_packet_json alias-creds \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 20000)"
    [[ "$(cat "$ARTIFACT_DIR/alias-creds.exit")" -eq 0 ]] || return 1
    [[ "$output" != *fixtureAlias* ]] || return 1
    jq -e '.status == "pass" and
      ((.context.cm.text | fromjson) | .PWD == "/public/workspace" and
        .apiKeyCount == 123456789 and .privateKeyCount == 123456789 and
        (.document | fromjson | .publicCount == 4) and
        .unconfigured == {"apiKey":"","MYSQL_PWD":null,"secretKey":false}) and
      (.context.cm.text | contains("\"eventId\":9007199254740993")) and
      (.context.cass.text | contains("PWD=/public/workspace")) and
      (.context.cass.text | contains("apiKeyCount=123456789")) and
      (.context.cass.text | contains("privateKeyCount=123456789"))' <<<"$output" >/dev/null || return 1
    markdown_output="$(run_packet_markdown alias-creds-markdown \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 20000)"
    [[ "$(cat "$ARTIFACT_DIR/alias-creds-markdown.exit")" -eq 0 ]] || return 1
    [[ "$markdown_output" != *fixtureAlias* ]] || return 1
    [[ "$markdown_output" == *"PWD=/public/workspace"* ]] || return 1
    [[ "$markdown_output" == *"apiKeyCount=123456789"* ]] || return 1
    [[ "$markdown_output" == *"privateKeyCount=123456789"* ]] || return 1
    cmp -s "$cm" "$cm.before" || return 1
    cmp -s "$cass" "$cass.before" || return 1
    pass "context_credential_aliases_preserve_public_metadata"
}

test_quoted_credential_families_are_redacted() {
    local bead agents readme cm cass output markdown_output
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$ARTIFACT_DIR/quoted-credentials-cm.json"
    cass="$ARTIFACT_DIR/quoted-credentials-cass.txt"
    cat > "$cm" <<'JSON'
{"snippet":"PASSWORD=\"fixtureQuotedPasswordFirst fixtureQuotedPasswordTail\"\nTOKEN='fixtureQuotedTokenFirst fixtureQuotedTokenTail'\nPUBLIC_STATUS=\"deploy ready\"","publicLabel":"password rotation guidance","tokenCount":"public token count","passwordPolicy":"public policy","eventId":9007199254740993}
JSON
    cat > "$cass" <<'TEXT'
PASSWORD="fixtureQuotedPasswordFirst fixtureQuotedPasswordTail"
passwd='fixtureQuotedPasswdFirst fixtureQuotedPasswdTail'
DB_PASSWORD="fixtureQuotedDatabaseFirst fixtureQuotedDatabaseTail"
AUTH_TOKEN='fixtureQuotedAuthFirst fixtureQuotedAuthTail'
AWS_SECRET_ACCESS_KEY="fixtureQuotedAccessFirst fixtureQuotedAccessTail"
APPLICATION_SECRET=fixtureQuotedUnquoted
PASSWORD="fixtureQuotedEscapeFirst \"fixtureQuotedEscapeTail"
TOKEN=\"fixtureQuotedNestedFirst \\\"fixtureQuotedNestedTail\"
PUBLIC_STATUS="deploy ready"
tokenCount=public-count
passwordPolicy=public-policy
SECRET="fixtureQuotedIncompleteFirst fixtureQuotedIncompleteTail
TEXT
    cp "$cm" "$cm.before"
    cp "$cass" "$cass.before"
    output="$(run_packet_json quoted-credentials \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 20000)"
    markdown_output="$(run_packet_markdown quoted-credentials-markdown \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 20000)"
    [[ "$(cat "$ARTIFACT_DIR/quoted-credentials.exit")" -eq 0 &&
       "$(cat "$ARTIFACT_DIR/quoted-credentials-markdown.exit")" -eq 0 ]] || return 1
    [[ "$output" != *fixtureQuoted* && "$markdown_output" != *fixtureQuoted* ]] || return 1
    jq -e '.status == "pass" and
      ((.context.cm.text | fromjson) |
        .snippet == "PASSWORD=\"[redacted]\"\nTOKEN=\u0027[redacted]\u0027\nPUBLIC_STATUS=\"deploy ready\"" and
        .publicLabel == "password rotation guidance" and
        .tokenCount == "public token count" and .passwordPolicy == "public policy") and
      (.context.cm.text | contains("\"eventId\":9007199254740993")) and
      (.context.cass.text | contains("PUBLIC_STATUS=\"deploy ready\"")) and
      (.context.cass.text | contains("tokenCount=public-count")) and
      (.context.cass.text | contains("passwordPolicy=public-policy"))' <<<"$output" >/dev/null || return 1
    [[ "$markdown_output" == *'PUBLIC_STATUS="deploy ready"'* &&
       "$markdown_output" == *tokenCount=public-count* &&
       "$markdown_output" == *passwordPolicy=public-policy* ]] || return 1
    cmp -s "$cm" "$cm.before" || return 1
    cmp -s "$cass" "$cass.before" || return 1
    pass "quoted_credential_families_are_redacted"
}

test_oauth_credentials_are_redacted_in_actual_packets() {
    local bead agents readme cm cass output markdown_output
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$ARTIFACT_DIR/oauth-cm.json"
    cass="$ARTIFACT_DIR/oauth-cass.txt"
    cat > "$cm" <<'JSON'
{"access_token":"fixtureOAuthAccess","refresh_token":"fixtureOAuthRefresh","id_token":"fixtureOAuthId","auth_token":"fixtureOAuthAuth","client_secret":"fixtureOAuthClient","accessToken":"fixtureOAuthCamelAccess","refreshToken":"fixtureOAuthCamelRefresh","idToken":"fixtureOAuthCamelId","authToken":"fixtureOAuthCamelAuth","clientSecret":"fixtureOAuthCamelClient","azure_client_secret":"fixtureOAuthQualified","oauth.access_token":"fixtureOAuthDotted","oauth-refreshToken":"fixtureOAuthDashed","document":"{\"access_\\u0074oken\":\"fixtureOAuthEncoded\\\"fixtureOAuthTail\",\"publicId\":9007199254740993}","client_id":"public-client","token_type":"Bearer","expires_in":3600,"scope":"read write","tokenCount":123,"accessTokenCount":7,"refreshTokenCount":8,"clientSecretPolicy":"rotate quarterly","eventId":9007199254740993,"unconfigured":{"access_token":"","refreshToken":null,"client_secret":false,"auth_token":0}}
JSON
    cat > "$cass" <<'TEXT'
access_token=fixtureOAuthShell
refreshToken='fixtureOAuthFirst fixtureOAuthLast'
idToken="fixtureOAuthIdFirst \"fixtureOAuthIdTail"
auth_token="fixtureOAuthAuthFirst fixtureOAuthAuthTail"
service_auth_token=fixtureOAuthQualifiedShell
service.clientSecret="fixtureOAuthDottedFirst fixtureOAuthDottedTail"
access_token=\"fixtureOAuthEscapedFirst \\\"fixtureOAuthEscapedTail\"
client_id=public-client
token_type=Bearer
expires_in=3600
scope="read write"
accessTokenCount=7
refreshTokenCount=8
clientSecretPolicy="rotate quarterly"
client_secret="fixtureOAuthIncompleteFirst fixtureOAuthIncompleteTail
TEXT
    cp "$cm" "$cm.before"
    cp "$cass" "$cass.before"
    output="$(run_packet_json oauth-creds \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 20000)"
    markdown_output="$(run_packet_markdown oauth-creds-markdown \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 20000)"
    [[ "$(cat "$ARTIFACT_DIR/oauth-creds.exit")" -eq 0 &&
       "$(cat "$ARTIFACT_DIR/oauth-creds-markdown.exit")" -eq 0 ]] || return 1
    [[ "$output" != *fixtureOAuth* && "$markdown_output" != *fixtureOAuth* ]] || return 1
    jq -e '.status == "pass" and
      ((.context.cm.text | fromjson) |
        ([.access_token, .refresh_token, .id_token, .auth_token, .client_secret,
          .accessToken, .refreshToken, .idToken, .authToken, .clientSecret,
          .azure_client_secret, .["oauth.access_token"], .["oauth-refreshToken"]]
          | all(. == "[redacted]")) and
        (.document | fromjson | .access_token == "[redacted]") and
        (.document | contains("\"publicId\":9007199254740993")) and
        .client_id == "public-client" and .token_type == "Bearer" and
        .expires_in == 3600 and .scope == "read write" and .tokenCount == 123 and
        .accessTokenCount == 7 and .refreshTokenCount == 8 and
        .clientSecretPolicy == "rotate quarterly" and
        .unconfigured == {"access_token":"","refreshToken":null,"client_secret":false,"auth_token":0}) and
      (.context.cm.text | contains("\"eventId\":9007199254740993"))' <<<"$output" >/dev/null || return 1
    [[ "$markdown_output" == *client_id=public-client* &&
       "$markdown_output" == *token_type=Bearer* &&
       "$markdown_output" == *expires_in=3600* &&
       "$markdown_output" == *'scope="read write"'* &&
       "$markdown_output" == *accessTokenCount=7* &&
       "$markdown_output" == *refreshTokenCount=8* &&
       "$markdown_output" == *'clientSecretPolicy="rotate quarterly"'* ]] || return 1
    cmp -s "$cm" "$cm.before" || return 1
    cmp -s "$cass" "$cass.before" || return 1
    pass "oauth_credentials_are_redacted_in_actual_packets"
}

test_authorization_credentials_are_redacted_in_actual_packets() {
    local bead agents readme cm cass output markdown_output
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$ARTIFACT_DIR/authorization-cm.json"
    cass="$ARTIFACT_DIR/authorization-cass.txt"
    cat > "$cm" <<'JSON'
{"headers":{"Authorization":"bEaReR fixtureHeaderBearer","Proxy-Authorization":"Basic fixtureHeaderBasic","aUtHoRiZaTiOn":"Digest username=\"fixtureHeaderUser\", response=\"fixtureHeaderResponse\"","pRoXy-AuThOrIzAtIoN":"fixtureHeaderOpaque"},"document":"{\"Authoriz\\u0061tion\":\"Bearer fixtureHeaderEncoded\\\"fixtureHeaderTail\",\"publicId\":9007199254740993}","snippet":"Authorization: Bearer fixtureHeaderSnippet\npRoXy-AuThOrIzAtIoN: bAsIc fixtureHeaderProxySnippet\nX-Public-Header: visible","authorizationCount":4,"authorizationPolicy":"public policy","Proxy-Authorization-Policy":"public proxy policy","eventId":9007199254740993,"unconfigured":{"Authorization":"","Proxy-Authorization":null}}
JSON
    cat > "$cass" <<'TEXT'
Authorization: Bearer fixtureHeaderExisting
aUtHoRiZaTiOn: bEaReR fixtureHeaderMixed
pRoXy-AuThOrIzAtIoN: bAsIc fixtureHeaderProxy
Authorization: Digest username="fixtureHeaderUser", response="fixtureHeaderResponse"
Authorization: "Bearer fixtureHeaderQuotedFirst fixtureHeaderQuotedLast"
Proxy-Authorization: 'Basic fixtureHeaderSingleFirst fixtureHeaderSingleLast'
Authorization: \"Bearer fixtureHeaderEscapedFirst \\\"fixtureHeaderEscapedLast\"
curl -H "Authorization: Bearer fixtureHeaderCurl" https://example.com/public
X-Public-Header: visible
Authorization-Policy: public policy
authorizationCount=4
TEXT
    cp "$cm" "$cm.before"
    cp "$cass" "$cass.before"
    output="$(run_packet_json authorization-creds \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 20000)"
    markdown_output="$(run_packet_markdown authorization-creds-markdown \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 20000)"
    [[ "$(cat "$ARTIFACT_DIR/authorization-creds.exit")" -eq 0 &&
       "$(cat "$ARTIFACT_DIR/authorization-creds-markdown.exit")" -eq 0 ]] || return 1
    [[ "$output" != *fixtureHeader* && "$markdown_output" != *fixtureHeader* ]] || return 1
    jq -e '.status == "pass" and
      ((.context.cm.text | fromjson) |
        (.headers | all(. == "[redacted]")) and
        (.document | fromjson | .Authorization == "[redacted]") and
        (.document | contains("\"publicId\":9007199254740993")) and
        (.snippet | contains("X-Public-Header: visible")) and
        .authorizationCount == 4 and .authorizationPolicy == "public policy" and
        .["Proxy-Authorization-Policy"] == "public proxy policy" and
        .unconfigured == {"Authorization":"","Proxy-Authorization":null}) and
      (.context.cm.text | contains("\"eventId\":9007199254740993"))' <<<"$output" >/dev/null || return 1
    [[ "$markdown_output" == *https://example.com/public* &&
       "$markdown_output" == *'X-Public-Header: visible'* &&
       "$markdown_output" == *'Authorization-Policy: public policy'* &&
       "$markdown_output" == *authorizationCount=4* ]] || return 1
    cmp -s "$cm" "$cm.before" || return 1
    cmp -s "$cass" "$cass.before" || return 1
    pass "authorization_credentials_are_redacted_in_actual_packets"
}

test_sanitizer_masks_complete_header_values_without_touching_public_text() {
    local input output
    input="$(cat <<'TEXT'
AUTHORIZATION: bEaReR fixtureDirectOpaque
pRoXy-AuThOrIzAtIoN: BaSiC fixtureDirectProxy
Authorization: "Bearer fixtureDirectMultilineFirst
fixtureDirectMultilineTail"
request Authorization: Digest username="fixtureDirectLoggedUser", response="fixtureDirectLoggedResponse"
request Proxy-Authorization: bAsIc "fixtureDirectLoggedQuotedFirst fixtureDirectLoggedQuotedTail"
curl -H 'Authorization: Bearer fixtureDirectFirst fixtureDirectTail' https://example.com/public
curl -H 'Proxy-Authorization: Digest username="fixtureDirectUser", response="fixtureDirectResponse"' https://example.com/digest
oauth.access_token="fixtureDirectQuoted \"fixtureDirectQuotedTail"
token_type=Bearer
client_id=public-client
accessTokenCount=7
refreshTokenCount=8
clientSecretPolicy="rotate quarterly"
authorizationCount=4
Authorization-Policy: public policy
TEXT
)"
    output="$(bash -c 'source "$1" --help >/dev/null; swarm_packet_sanitize_context_text "$2"' \
        _ "$SWARM_PACKET_SH" "$input")" || return 1
    [[ "$output" != *fixtureDirect* &&
       "$output" == *https://example.com/public* &&
       "$output" == *https://example.com/digest* &&
       "$output" == *token_type=Bearer* &&
       "$output" == *client_id=public-client* &&
       "$output" == *accessTokenCount=7* &&
       "$output" == *refreshTokenCount=8* &&
       "$output" == *'clientSecretPolicy="rotate quarterly"'* &&
       "$output" == *authorizationCount=4* &&
       "$output" == *'Authorization-Policy: public policy'* ]] || return 1
    pass "sanitizer_masks_complete_header_values_without_touching_public_text"
}

test_escaped_json_credentials_preserve_public_context() {
    local bead agents readme cm cass output markdown_output
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$ARTIFACT_DIR/escaped-credentials-cm.json"
    cass="$ARTIFACT_DIR/escaped-credentials-cass.json"
    cat > "$cm" <<'JSON'
{"password":"fixtureJsonPasswordFirst\"fixtureJsonPasswordTail","passwd":"fixtureJsonPasswdFirst\\fixtureJsonPasswdTail","secret":"fixtureJsonSecretFirst\nfixtureJsonSecretTail","token":"fixtureJsonTokenFirst\tfixtureJsonTokenTail","DB_PASSWORD":"fixtureJsonPrefixedFirst\"fixtureJsonPrefixedTail","document":"{\"password\":\"fixtureJsonNestedFirst\\\"fixtureJsonNestedTail\",\"publicLabel\":\"nested visible\",\"eventId\":9007199254740993}","snippet":"TOKEN=\"fixtureJsonSnippetFirst \\\"fixtureJsonSnippetTail\"","publicLabel":"credentials review \"quoted\" guide","passwordCount":"public count","publicPath":"C:\\public\\workspace","eventId":9007199254740993,"unconfigured":{"password":"","passwd":null,"secret":false,"token":0}}
JSON
    cat > "$cass" <<'JSON'
{"results":[{"document":"{\"passwd\":\"fixtureJsonCassFirst\\\"fixtureJsonCassTail\",\"publicLabel\":\"cass visible\",\"eventId\":9007199254740993}","PASSWORD":"fixtureJsonUpperFirst\"fixtureJsonUpperTail","pass\u0077ord":"fixtureJsonEscapedKeyFirst\"fixtureJsonEscapedKeyTail"}]}
JSON
    cp "$cm" "$cm.before"
    cp "$cass" "$cass.before"
    output="$(run_packet_json escaped-credentials \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 20000)"
    markdown_output="$(run_packet_markdown escaped-credentials-markdown \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 20000)"
    [[ "$(cat "$ARTIFACT_DIR/escaped-credentials.exit")" -eq 0 &&
       "$(cat "$ARTIFACT_DIR/escaped-credentials-markdown.exit")" -eq 0 ]] || return 1
    [[ "$output" != *fixtureJson* && "$markdown_output" != *fixtureJson* ]] || return 1
    jq -e '.status == "pass" and
      ((.context.cm.text | fromjson) |
        [.password, .passwd, .secret, .token, .DB_PASSWORD] ==
          ["[redacted]", "[redacted]", "[redacted]", "[redacted]", "[redacted]"] and
        (.document | fromjson | .password == "[redacted]" and .publicLabel == "nested visible") and
        (.document | contains("\"eventId\":9007199254740993")) and
        .snippet == "TOKEN=\"[redacted]\"" and
        .publicLabel == "credentials review \"quoted\" guide" and
        .passwordCount == "public count" and .publicPath == "C:\\public\\workspace" and
        .unconfigured == {"password":"","passwd":null,"secret":false,"token":0}) and
      (.context.cm.text | contains("\"eventId\":9007199254740993")) and
      ((.context.cass.text | fromjson | .results[0]) |
        .PASSWORD == "[redacted]" and .password == "[redacted]" and
        (.document | fromjson | .passwd == "[redacted]" and .publicLabel == "cass visible") and
        (.document | contains("\"eventId\":9007199254740993")))' <<<"$output" >/dev/null || return 1
    [[ "$markdown_output" == *'9007199254740993'* &&
       "$markdown_output" == *'nested visible'* &&
       "$markdown_output" == *'cass visible'* &&
       "$markdown_output" == *'public count'* ]] || return 1
    cmp -s "$cm" "$cm.before" || return 1
    cmp -s "$cass" "$cass.before" || return 1
    pass "escaped_json_credentials_preserve_public_context"
}

test_packet_refuses_failed_credential_redaction() {
    local bead agents readme cm cass output real_jq bin_dir phase marked_bead
    real_jq="$(command -v jq)"
    bin_dir="$ARTIFACT_DIR/unavailable-redactor-bin"
    mkdir -p "$bin_dir"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf 'real_jq=%q\n' "$real_jq"
        printf '%s\n' \
            'if [[ "$1" == -Rrs ]]; then' \
            '  input=$(cat)' \
            '  if [[ "$input" == *fixtureAliasRedactorUnavailable* ]]; then' \
            '    echo "redactor unavailable" >&2; exit 71' \
            '  fi' \
            '  printf "%s" "$input" | "$real_jq" "$@"' \
            'else' \
            '  exec "$real_jq" "$@"' \
            'fi'
    } > "$bin_dir/jq"
    chmod +x "$bin_dir/jq"
    for phase in title labels description agents readme cm cass; do
        bead="$(bead_fixture)"
        agents="$(agents_fixture)"
        readme="$(readme_fixture)"
        cm="$(cm_fixture)"
        cass="$(cass_fixture)"
        case "$phase" in
            title|description|labels)
                marked_bead="$ARTIFACT_DIR/unavailable-redactor-$phase-bead.json"
                jq --arg phase "$phase" '.[0][$phase] = (if $phase == "labels"
                  then ["fixtureAliasRedactorUnavailable"] else "fixtureAliasRedactorUnavailable" end)' \
                    "$bead" > "$marked_bead"
                bead="$marked_bead"
                ;;
            agents) printf '%s\n' 'fixtureAliasRedactorUnavailable' > "$agents" ;;
            readme) printf '%s\n' 'fixtureAliasRedactorUnavailable' > "$readme" ;;
            cm) printf '%s\n' '{"apiKey":"fixtureAliasRedactorUnavailable"}' > "$cm" ;;
            cass) printf '%s\n' '{"apiKey":"fixtureAliasRedactorUnavailable"}' > "$cass" ;;
        esac
        output="$(PATH="$bin_dir:$PATH" run_packet_json "unavailable-redactor-$phase" \
            --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
            --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
            --agent-name FixtureAgent --max-chars 20000)"
        [[ "$(cat "$ARTIFACT_DIR/unavailable-redactor-$phase.exit")" -ne 0 ]] || return 1
        [[ "$output" != *'"packet_markdown"'* ]] || return 1
        [[ "$output" != *fixtureAlias* ]] || return 1
    done
    pass "packet_refuses_failed_credential_redaction"
}

test_packet_preserves_empty_labels() {
    local bead="$ARTIFACT_DIR/empty-label-bead.json"
    local source_bead agents readme cm cass output
    source_bead="$(bead_fixture)"
    jq '.[0].labels = []' "$source_bead" > "$bead"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$(cm_fixture)"
    cass="$(cass_fixture)"
    output="$(run_packet_json empty-labels \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 9000)"
    [[ "$(cat "$ARTIFACT_DIR/empty-labels.exit")" -eq 0 ]] || return 1
    jq -e '.status == "pass" and .bead.labels == []' <<<"$output" >/dev/null || return 1
    pass "packet_preserves_empty_labels"
}

test_packet_rejects_malformed_labels_without_echoing_values() {
    local source_bead bead agents readme cm cass output labels
    source_bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$(cm_fixture)"
    cass="$(cass_fixture)"
    for labels in '"fixtureLabelPrivateValue123456"' \
        '{"field":"fixtureLabelPrivateValue123456"}' \
        '["coordination",{"field":"fixtureLabelPrivateValue123456"}]' \
        'false' '42' '[null]'; do
        bead="$(mktemp "$ARTIFACT_DIR/malformed-labels.XXXXXX.json")"
        jq --argjson labels "$labels" '.[0].labels = $labels' "$source_bead" > "$bead"
        output="$(run_packet_json malformed-labels \
            --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
            --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
            --agent-name FixtureAgent --max-chars 9000)"
        [[ "$(cat "$ARTIFACT_DIR/malformed-labels.exit")" -eq 2 ]] || return 1
        [[ "$output" != *"fixtureLabelPrivateValue123456"* ]] || return 1
        [[ "$output" == *"Bead labels must be an array of strings"* ]] || return 1
    done
    pass "packet_rejects_malformed_labels_without_echoing_values"
}

test_packet_preserves_label_string_boundaries() {
    local source_bead bead agents readme cm cass output
    source_bead="$(bead_fixture)"
    bead="$ARTIFACT_DIR/label-boundaries.json"
    jq '.[0].labels = ["first\nsecond", "--label"]' "$source_bead" > "$bead"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$(cm_fixture)"
    cass="$(cass_fixture)"
    output="$(run_packet_json label-boundaries \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 9000)"
    [[ "$(cat "$ARTIFACT_DIR/label-boundaries.exit")" -eq 0 ]] || return 1
    jq -e '.status == "pass" and .bead.labels == ["first\nsecond", "--label"]' <<<"$output" >/dev/null || return 1
    pass "packet_preserves_label_string_boundaries"
}

test_packet_metadata_keeps_tool_names() {
    local source_bead bead agents readme cm cass output
    source_bead="$(bead_fixture)"
    bead="$ARTIFACT_DIR/tool-name-bead.json"
    jq '.[0].title = "cargo build cache" | .[0].labels = ["bv", "br"]' "$source_bead" > "$bead"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$(cm_fixture)"
    cass="$(cass_fixture)"
    output="$(run_packet_json tool-name-metadata \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 9000)"
    [[ "$(cat "$ARTIFACT_DIR/tool-name-metadata.exit")" -eq 0 ]] || return 1
    jq -e '.status == "pass" and .bead.title == "cargo build cache" and
      .bead.labels == ["bv", "br"] and
      (.context.agents_excerpt | contains("rch exec -- cargo test"))' <<<"$output" >/dev/null || return 1
    pass "packet_metadata_keeps_tool_names"
}

test_packet_removes_private_key_bodies_and_keeps_public_context() {
    local bead agents readme cm cass output
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$ARTIFACT_DIR/private-key-cm.txt"
    cass="$ARTIFACT_DIR/private-key-cass.json"
    printf '%s\n' 'Public context before
-----BEGIN OPENSSH PRIVATE KEY-----
fixtureCompletePrivateMaterial123456
-----END OPENSSH PRIVATE KEY-----
Public context after' > "$cm"
    printf '%s\n' '{"summary":"before -----BEGIN RSA PRIVATE KEY-----\nfixtureInlinePrivateMaterial123456\n-----END RSA PRIVATE KEY----- after; -----BEGIN PRIVATE KEY-----\nfixtureTruncatedPrivateMaterial123456"}' > "$cass"
    output="$(run_packet_json private-key-body \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --cass-file "$cass" --repo "$REPO_ROOT" \
        --agent-name FixtureAgent --max-chars 12000)"
    [[ "$(cat "$ARTIFACT_DIR/private-key-body.exit")" -eq 0 ]] || return 1
    jq -e '.status == "pass" and
      (.context.cm.text | contains("Public context before")) and
      (.context.cm.text | contains("Public context after")) and
      (.context.cm.text | contains("[private key redacted]")) and
      (.context.cass.text | contains("before [private key redacted] after;"))' <<<"$output" >/dev/null || return 1
    [[ "$output" != *"fixtureCompletePrivateMaterial123456"* ]] || return 1
    [[ "$output" != *"fixtureInlinePrivateMaterial123456"* ]] || return 1
    [[ "$output" != *"fixtureTruncatedPrivateMaterial123456"* ]] || return 1
    pass "packet_removes_private_key_bodies_and_keeps_public_context"
}

run_live_context_packet() {
    local name="$1" bin_dir="$2"
    shift 2
    local status=0
    PATH="$bin_dir:$PATH" bash "$SWARM_PACKET_SH" --json "$@" \
        > "$ARTIFACT_DIR/$name.output.json" 2> "$ARTIFACT_DIR/$name.stderr" || status=$?
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    cat "$ARTIFACT_DIR/$name.output.json"
}

test_live_search_requests_read_only_snippets() {
    local bead agents readme cm output bin_dir="$ARTIFACT_DIR/read-only-cli"
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    cm="$(cm_fixture)"
    mkdir -p "$bin_dir"
    # CLI double: require the read-only protocol, not a canned success path.
    cat > "$bin_dir/cass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$(dirname "$0")/argv"
[[ "$1" == search && "$3" == --workspace ]] || exit 64
readonly_search=false lexical=false snippets=false
while (( $# )); do
    case "$1" in
        --no-maintenance) readonly_search=true ;;
        --mode) [[ "${2:-}" == lexical ]] && lexical=true ;;
        --fields) [[ "${2:-}" == *snippet* ]] && snippets=true ;;
    esac
    shift
done
[[ "$readonly_search" == true && "$lexical" == true && "$snippets" == true ]] || exit 65
printf '%s\n' '{"hits":[{"snippet":"Useful retrieved session detail","title":"Private test session"}]}'
EOF
    chmod +x "$bin_dir/cass"
    output="$(run_live_context_packet read-only-cli "$bin_dir" \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --cm-file "$cm" --repo "$REPO_ROOT" --max-chars 12000)"
    [[ "$(cat "$ARTIFACT_DIR/read-only-cli.exit")" -eq 0 ]] || return 1
    jq -e '.status == "pass" and .context.cass.status == "available" and
      .safety.read_only == true and .safety.live_cm_context_requested == false and
      (.context.cass.text | contains("Useful retrieved session detail"))' <<<"$output" >/dev/null || return 1
    [[ "$(sed -n '4p' "$bin_dir/argv")" == "$REPO_ROOT" ]] || return 1
    pass "live_search_requests_read_only_snippets"
}

test_live_context_failures_keep_exit_status() {
    local bead agents readme output bin_dir="$ARTIFACT_DIR/failing-cli"
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/cm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"error":"Failed CM output must not become context"}'
printf '%s\n' 'CM command diagnostic' >&2
exit 23
EOF
    cat > "$bin_dir/cass" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'Failed CASS output must not become context'
exit 124
EOF
    chmod +x "$bin_dir/cm" "$bin_dir/cass"
    output="$(run_live_context_packet failing-cli "$bin_dir" \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --repo "$REPO_ROOT" --max-chars 12000)"
    [[ "$(cat "$ARTIFACT_DIR/failing-cli.exit")" -eq 0 ]] || return 1
    jq -e '.status == "warn" and .context.cm.status == "missing" and
      .context.cass.status == "missing" and
      (.warnings | index("cm context unavailable: command exited 23")) != null and
      (.warnings | index("cass context unavailable: command exited 124")) != null' <<<"$output" >/dev/null || return 1
    [[ "$output" != *"Failed CM output"* && "$output" != *"Failed CASS output"* ]] || return 1
    pass "live_context_failures_keep_exit_status"
}

test_live_context_keeps_diagnostics_out_of_prompts() {
    local bead agents readme output bin_dir="$ARTIFACT_DIR/diagnostic-cli"
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/cm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"relevantBullets":[{"content":"Actual rule payload"}]}'
printf '%s\n' 'CLI diagnostic separate from CM payload' >&2
EOF
    cat > "$bin_dir/cass" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"hits":[{"snippet":"Actual history payload"}]}'
printf '%s\n' 'CLI diagnostic separate from CASS payload' >&2
EOF
    chmod +x "$bin_dir/cm" "$bin_dir/cass"
    output="$(run_live_context_packet diagnostic-cli "$bin_dir" \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --repo "$REPO_ROOT" --max-chars 12000)"
    [[ "$(cat "$ARTIFACT_DIR/diagnostic-cli.exit")" -eq 0 ]] || return 1
    jq -e '.status == "pass" and
      .safety.read_only == false and .safety.live_cm_context_requested == true and
      (.packet_markdown | contains("Live CM retrieval may update memory/history caches.")) and
      (.context.cm.text | fromjson | .relevantBullets[0].content) == "Actual rule payload" and
      (.context.cass.text | fromjson | .hits[0].snippet) == "Actual history payload"' <<<"$output" >/dev/null || return 1
    [[ "$output" != *"CLI diagnostic"* ]] || return 1
    [[ "$(cat "$ARTIFACT_DIR/diagnostic-cli.stderr")" == *"separate from CM payload"* ]] || return 1
    [[ "$(cat "$ARTIFACT_DIR/diagnostic-cli.stderr")" == *"separate from CASS payload"* ]] || return 1
    pass "live_context_keeps_diagnostics_out_of_prompts"
}

test_empty_and_disabled_live_context_remain_distinct() {
    local bead agents readme output bin_dir="$ARTIFACT_DIR/empty-cli"
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/cm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' called >> "$(dirname "$0")/calls"
EOF
    cp "$bin_dir/cm" "$bin_dir/cass"
    chmod +x "$bin_dir/cm" "$bin_dir/cass"
    output="$(run_live_context_packet empty-cli "$bin_dir" \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --repo "$REPO_ROOT" --max-chars 12000)"
    jq -e '.status == "warn" and
      (.warnings | index("cm context unavailable: command returned no output")) != null and
      (.warnings | index("cass context unavailable: command returned no output")) != null' <<<"$output" >/dev/null || return 1
    [[ "$(wc -l < "$bin_dir/calls")" -eq 2 ]] || return 1
    output="$(run_live_context_packet disabled-cli "$bin_dir" \
        --bead-file "$bead" --agents-file "$agents" --readme-file "$readme" \
        --repo "$REPO_ROOT" --no-live-context --max-chars 12000)"
    jq -e '.status == "warn" and
      (.warnings | index("cm context unavailable: no fixture file supplied and live context disabled")) != null and
      (.warnings | index("cass context unavailable: no fixture file supplied and live context disabled")) != null and
      .safety.read_only == true and .safety.live_cm_context_requested == false' <<<"$output" >/dev/null || return 1
    [[ "$(cat "$ARTIFACT_DIR/empty-cli.exit")" -eq 0 &&
       "$(cat "$ARTIFACT_DIR/disabled-cli.exit")" -eq 0 ]] || return 1
    [[ "$(wc -l < "$bin_dir/calls")" -eq 2 ]] || return 1
    pass "empty_and_disabled_live_context_remain_distinct"
}

run_test() {
    local name="$1"
    if "$name"; then
        return 0
    fi
    fail "$name"
}

test_live_bead_reader_uses_jsonl_only() {
    local bead agents readme output bin_dir="$ARTIFACT_DIR/jsonl-reader-cli"
    bead="$(bead_fixture)"
    agents="$(agents_fixture)"
    readme="$(readme_fixture)"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/br" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/argv"
[[ "$#" -eq 4 && "$1" == show && "$3" == --json && "$4" == --no-db ]] || exit 65
cat "$ACFS_PACKET_BEAD_FIXTURE"
EOF
    chmod +x "$bin_dir/br"
    output="$(ACFS_PACKET_BEAD_FIXTURE="$bead" run_live_context_packet jsonl-reader-cli "$bin_dir" \
        --bead bd-n968h --agents-file "$agents" --readme-file "$readme" \
        --repo "$REPO_ROOT" --no-live-context --max-chars 12000)"
    [[ "$(cat "$ARTIFACT_DIR/jsonl-reader-cli.exit")" -eq 0 ]] || return 1
    jq -e '.bead.id == "bd-n968h" and .safety.read_only == true and
      .safety.mutates_beads == false' <<<"$output" >/dev/null || return 1
    pass "live_bead_reader_uses_jsonl_only"
}

main() {
    command -v jq >/dev/null 2>&1 || {
        echo "jq is required for swarm packet tests" >&2
        exit 1
    }

    run_test test_json_packet_includes_required_workflow
    run_test test_markdown_packet_is_bounded
    run_test test_missing_cm_and_cass_warn_without_failing
    run_test test_generated_content_lint_blocks_unsafe_templates
    run_test test_context_service_credentials_are_redacted_before_packet_output
    run_test test_context_credential_aliases_preserve_public_metadata
    run_test test_quoted_credential_families_are_redacted
    run_test test_oauth_credentials_are_redacted_in_actual_packets
    run_test test_authorization_credentials_are_redacted_in_actual_packets
    run_test test_sanitizer_masks_complete_header_values_without_touching_public_text
    run_test test_escaped_json_credentials_preserve_public_context
    run_test test_packet_refuses_failed_credential_redaction
    run_test test_packet_preserves_empty_labels
    run_test test_packet_rejects_malformed_labels_without_echoing_values
    run_test test_packet_preserves_label_string_boundaries
    run_test test_packet_metadata_keeps_tool_names
    run_test test_packet_removes_private_key_bodies_and_keeps_public_context
    run_test test_live_search_requests_read_only_snippets
    run_test test_live_context_failures_keep_exit_status
    run_test test_live_context_keeps_diagnostics_out_of_prompts
    run_test test_empty_and_disabled_live_context_remain_distinct
    run_test test_live_bead_reader_uses_jsonl_only

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
