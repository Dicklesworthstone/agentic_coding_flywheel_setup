#!/usr/bin/env bash
# Test session sanitization patterns

source scripts/lib/session.sh

# Mock logging
log_error() { echo "ERROR: $1" >&2; }
log_warn() { echo "WARN: $1" >&2; }

# Test Data
# Construct keys dynamically to avoid secret scanning detection
# These must match the patterns in session.sh:
# Stripe: [rs]k_(live|test)_[a-zA-Z0-9]{24,}
# HuggingFace: hf_[a-zA-Z0-9]{34}

STRIPE_LIVE="sk_live_""123456789012345678901234"
STRIPE_TEST="sk_test_""123456789012345678901234"
HF_TOKEN="hf_""1234567890123456789012345678901234"

RAW_TEXT="
My OpenAI key is sk-12345678901234567890
My Anthropic key is sk-ant-12345678901234567890
My AWS key is AKIAIOSFODNN7EXAMPLE
My HuggingFace token is ${HF_TOKEN}
My Stripe live key is ${STRIPE_LIVE}
My Stripe test key is ${STRIPE_TEST}
Normal text should remain.
"

echo "Testing sanitize_content (Bash/sed)..."
SANITIZED=$(sanitize_content "$RAW_TEXT")

echo "$SANITIZED"

# verification
if echo "$SANITIZED" | grep -q "sk-12345"; then echo "FAIL: OpenAI leaked"; exit 1; fi
if echo "$SANITIZED" | grep -q "sk-ant-12345"; then echo "FAIL: Anthropic leaked"; exit 1; fi
if echo "$SANITIZED" | grep -q "AKIA"; then echo "FAIL: AWS leaked"; exit 1; fi
if echo "$SANITIZED" | grep -q "hf_"; then echo "FAIL: HuggingFace leaked"; exit 1; fi
if echo "$SANITIZED" | grep -q "sk_live_"; then echo "FAIL: Stripe live leaked"; exit 1; fi
if echo "$SANITIZED" | grep -q "sk_test_"; then echo "FAIL: Stripe test leaked"; exit 1; fi

echo "PASS: sanitize_content"

# Test JSON sanitization
echo "Testing sanitize_session_export (jq)..."
JSON_FILE=$(mktemp)
cat > "$JSON_FILE" <<EOF
{
  "schema_version": 1,
  "session_id": "test",
  "agent": "claude-code",
  "sanitized_transcript": [
    {
      "role": "user",
      "content": "My secret is ${HF_TOKEN}"
    },
    {
        "role": "assistant",
        "content": "I see your stripe key ${STRIPE_LIVE}"
    }
  ]
}
EOF

sanitize_session_export "$JSON_FILE"
SANITIZED_JSON=$(cat "$JSON_FILE")
rm "$JSON_FILE"

if echo "$SANITIZED_JSON" | grep -q "hf_"; then echo "FAIL: JSON HuggingFace leaked"; exit 1; fi
if echo "$SANITIZED_JSON" | grep -q "sk_live_"; then echo "FAIL: JSON Stripe leaked"; exit 1; fi

echo "PASS: sanitize_session_export"
