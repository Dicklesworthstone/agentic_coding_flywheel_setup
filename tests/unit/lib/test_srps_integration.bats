#!/usr/bin/env bats

# SRPS Integration Unit Tests
# Validates TypeScript data files and build integrity

load '../test_helper'

# ============================================================
# SETUP
# ============================================================

setup() {
    common_setup
    export WEB_DIR="$PROJECT_ROOT/apps/web"
}

teardown() {
    common_teardown
}

# ============================================================
# BUILD TESTS
# ============================================================

@test "TypeScript compilation succeeds with SRPS additions" {
    if ! command -v bun &>/dev/null; then
        skip "bun not available"
    fi

    log_info "Running TypeScript compilation check..."

    run bash -lc "cd '$WEB_DIR' && bun run type-check"

    assert_success
    log_pass "TypeScript compilation passed"
}

@test "Next.js build succeeds with SRPS additions (optional)" {
    if [[ -z "${ACFS_RUN_BUILD_TESTS:-}" ]]; then
        skip "Build tests disabled (set ACFS_RUN_BUILD_TESTS=1 to enable)"
    fi

    if ! command -v bun &>/dev/null; then
        skip "bun not available"
    fi

    log_info "Running Next.js build..."

    run bash -lc "cd '$WEB_DIR' && bun run build"

    assert_success
    log_pass "Next.js build passed"
}

# ============================================================
# DATA INTEGRITY TESTS
# ============================================================

@test "flywheel.ts contains SRPS tool entry" {
    log_info "Checking flywheel.ts for SRPS entry..."

    run grep -l 'id: "srps"' "$WEB_DIR/lib/flywheel.ts"

    assert_success
    log_pass "SRPS found in flywheel.ts"
}

@test "flywheel.ts contains SRPS workflow scenario" {
    log_info "Checking for SRPS workflow scenario..."

    run grep -l 'resource-protected-swarm' "$WEB_DIR/lib/flywheel.ts"

    assert_success
    log_pass "SRPS workflow scenario found"
}

@test "tldr-content.ts contains SRPS entry" {
    log_info "Checking tldr-content.ts for SRPS entry..."

    run grep -l 'id: "srps"' "$WEB_DIR/lib/tldr-content.ts"

    assert_success
    log_pass "SRPS found in tldr-content.ts"
}

@test "commands.ts contains sysmoni entry" {
    log_info "Checking commands.ts for sysmoni entry..."

    run grep -l 'name: "sysmoni"' "$WEB_DIR/lib/commands.ts"

    assert_success
    log_pass "sysmoni found in commands.ts"
}

@test "lessons.ts contains SRPS entry" {
    log_info "Checking lessons.ts for SRPS entry..."

    run grep -l 'slug: "srps"' "$WEB_DIR/lib/lessons.ts"

    assert_success
    log_pass "SRPS found in lessons.ts"
}

# ============================================================
# LESSON COMPONENT TESTS
# ============================================================

@test "srps-lesson.tsx exists" {
    log_info "Checking for srps-lesson.tsx..."

    [ -f "$WEB_DIR/components/lessons/srps-lesson.tsx" ]

    log_pass "srps-lesson.tsx exists"
}

@test "lessons/index.tsx imports SrpsLesson" {
    log_info "Checking lesson index for SRPS import..."

    run grep -l 'SrpsLesson' "$WEB_DIR/components/lessons/index.tsx"

    assert_success
    log_pass "SrpsLesson imported"
}

@test "lessons/index.tsx maps the srps slug to the SRPS lesson" {
    log_info "Checking lesson index maps srps..."

    run grep -A1 '^    "srps",$' "$WEB_DIR/components/lessons/index.tsx"

    assert_success
    assert_output --partial 'import("./srps-lesson").then((m) => ({ default: m.SrpsLesson }))'
    log_pass "srps slug mapped"
}

@test "srps-lesson.tsx exports SrpsLesson" {
    log_info "Checking srps-lesson exports SrpsLesson..."

    run grep -l '^export function SrpsLesson()' "$WEB_DIR/components/lessons/srps-lesson.tsx"

    assert_success
    log_pass "SrpsLesson exported"
}

# ============================================================
# MARKDOWN LESSON TEST
# ============================================================

@test "23_srps.md lesson file exists" {
    log_info "Checking for markdown lesson file..."

    [ -f "$PROJECT_ROOT/acfs/onboard/lessons/23_srps.md" ]

    log_pass "23_srps.md exists"
}

@test "23_srps.md has expected content structure" {
    log_info "Checking lesson content structure..."

    local lesson="$PROJECT_ROOT/acfs/onboard/lessons/23_srps.md"

    # Check for title
    grep -q "^# " "$lesson" || {
        log_fail "Missing title heading"
        return 1
    }

    # Check for command references
    grep -qiE "sysmoni|ananicy" "$lesson" || {
        log_fail "Missing SRPS command references"
        return 1
    }

    log_pass "Lesson content structure valid"
}

# ============================================================
# TLDR CONTENT VALIDATION
# ============================================================

@test "SRPS tldr entry has required fields" {
    log_info "Validating SRPS tldr entry fields..."

    local tldr="$WEB_DIR/lib/tldr-content.ts"

    # Extract SRPS block and check for required fields
    grep -A 50 'id: "srps"' "$tldr" | head -50 > /tmp/srps_block.txt

    grep -q 'name:' /tmp/srps_block.txt || { log_fail "Missing name field"; return 1; }
    grep -q 'shortName:' /tmp/srps_block.txt || { log_fail "Missing shortName field"; return 1; }
    grep -q 'whatItDoes:' /tmp/srps_block.txt || { log_fail "Missing whatItDoes field"; return 1; }
    grep -q 'synergies:' /tmp/srps_block.txt || { log_fail "Missing synergies field"; return 1; }

    rm -f /tmp/srps_block.txt
    log_pass "All required tldr fields present"
}

# ============================================================
# FLYWHEEL SYNERGY TESTS
# ============================================================

@test "SRPS has synergies defined in flywheel.ts" {
    log_info "Checking SRPS synergies..."

    local flywheel="$WEB_DIR/lib/flywheel.ts"

    # SRPS should connect to other tools
    grep -A 25 'id: "srps"' "$flywheel" | grep -q 'connectsTo' || {
        log_fail "SRPS missing connectsTo field"
        return 1
    }

    log_pass "SRPS has synergies defined"
}
