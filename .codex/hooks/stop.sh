#!/bin/bash
# planning-with-files: Stop hook for Codex

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
PLAN_DIR="$(sh "${HOOK_DIR}/resolve-plan-dir.sh" 2>/dev/null)"
PLAN_FILE="${PLAN_DIR:+${PLAN_DIR}/}task_plan.md"
PROGRESS_FILE="${PLAN_DIR:+${PLAN_DIR}/}progress.md"

relpath() {
    case "$1" in
        "${PWD}/"*) printf "%s" "${1#${PWD}/}" ;;
        *) printf "%s" "$1" ;;
    esac
}

if [ ! -f "$PLAN_FILE" ]; then
    exit 0
fi

TOTAL=$(grep -c "### Phase" "$PLAN_FILE" || true)
COMPLETE=$(grep -cF "**Status:** complete" "$PLAN_FILE" || true)
IN_PROGRESS=$(grep -cF "**Status:** in_progress" "$PLAN_FILE" || true)
PENDING=$(grep -cF "**Status:** pending" "$PLAN_FILE" || true)

if [ "$COMPLETE" -eq 0 ] && [ "$IN_PROGRESS" -eq 0 ] && [ "$PENDING" -eq 0 ]; then
    COMPLETE=$(grep -c "\[complete\]" "$PLAN_FILE" || true)
    IN_PROGRESS=$(grep -c "\[in_progress\]" "$PLAN_FILE" || true)
    PENDING=$(grep -c "\[pending\]" "$PLAN_FILE" || true)
fi

: "${TOTAL:=0}"
: "${COMPLETE:=0}"
: "${IN_PROGRESS:=0}"
: "${PENDING:=0}"

if [ "$COMPLETE" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
    echo "{\"followup_message\": \"[planning-with-files] ALL PHASES COMPLETE ($COMPLETE/$TOTAL). If the user has additional work, add new phases to $(relpath "$PLAN_FILE") before starting.\"}"
    exit 0
fi

echo "{\"followup_message\": \"[planning-with-files] Task incomplete ($COMPLETE/$TOTAL phases done). Update $(relpath "$PROGRESS_FILE"), then read $(relpath "$PLAN_FILE") and continue working on the remaining phases.\"}"
exit 0
