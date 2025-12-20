#!/usr/bin/env bash
set -euo pipefail

ACFS_HOME="${ACFS_HOME:-$HOME/.acfs}"
LESSONS_DIR="$ACFS_HOME/onboard/lessons"

LESSONS=(
  "00_welcome.md"
  "01_linux_basics.md"
  "02_ssh_basics.md"
  "03_tmux_basics.md"
  "04_agents_login.md"
  "05_ntm_core.md"
  "06_ntm_command_palette.md"
  "07_flywheel_loop.md"
)

usage() {
  cat <<'EOF'
onboard - ACFS onboarding tutorial

Usage:
  onboard                Run all lessons in order
  onboard --list         List available lessons
  onboard <n>            Run a single lesson (0-7)
  onboard --help         Show this help

Notes:
- Lessons live in ~/.acfs/onboard/lessons
- Re-run the ACFS installer if lessons are missing
EOF
}

print_list() {
  local i=0
  for lesson in "${LESSONS[@]}"; do
    printf "%d  %s\n" "$i" "$lesson"
    i=$((i + 1))
  done
}

_pager() {
  if command -v bat &>/dev/null; then
    bat --paging=always --style=plain
    return 0
  fi
  if command -v less &>/dev/null; then
    less -R
    return 0
  fi
  cat
}

show_lesson_file() {
  local lesson_file="$1"
  local path="$LESSONS_DIR/$lesson_file"

  if [[ ! -f "$path" ]]; then
    echo "✖ Lesson not found: $path" >&2
    echo "    Fix: re-run the ACFS installer to (re)install onboarding lessons." >&2
    return 1
  fi

  echo "" >&2
  echo "============================================================" >&2
  echo "Lesson: $lesson_file" >&2
  echo "============================================================" >&2
  echo "" >&2

  _pager <"$path"
}

pause_if_tty() {
  if [[ -t 0 ]]; then
    read -r -p "Press Enter to continue..." _ </dev/tty || true
  fi
}

run_all() {
  local lesson
  for lesson in "${LESSONS[@]}"; do
    show_lesson_file "$lesson"
    pause_if_tty
  done
}

main() {
  case "${1:-}" in
    "" )
      run_all
      ;;
    --help|-h )
      usage
      ;;
    --list )
      print_list
      ;;
    [0-9] )
      local idx="$1"
      if (( idx < 0 || idx >= ${#LESSONS[@]} )); then
        echo "✖ Invalid lesson index: $idx" >&2
        echo "    Try: onboard --list" >&2
        exit 1
      fi
      show_lesson_file "${LESSONS[$idx]}"
      ;;
    * )
      echo "✖ Unknown argument: $1" >&2
      echo "    Try: onboard --help" >&2
      exit 1
      ;;
  esac
}

main "$@"

