#!/bin/sh
# planning-with-files: Post-tool-use hook for Codex skill installs.

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
PLAN_DIR="$(sh "${SCRIPT_DIR}/resolve-plan-dir.sh" 2>/dev/null)"
PLAN_FILE="${PLAN_DIR:+${PLAN_DIR}/}task_plan.md"
PROGRESS_FILE="${PLAN_DIR:+${PLAN_DIR}/}progress.md"

relpath() {
    case "$1" in
        "${PWD}/"*) printf "%s" "${1#${PWD}/}" ;;
        *) printf "%s" "$1" ;;
    esac
}

if [ -f "$PLAN_FILE" ]; then
    echo "[planning-with-files] Update $(relpath "$PROGRESS_FILE") with what you just did. If a phase is now complete, update $(relpath "$PLAN_FILE") status."
fi
exit 0
