#!/bin/sh
# planning-with-files: resolve active plan directory.
#
# Resolution order:
#   1. $PLAN_ID env var → ./.planning/$PLAN_ID/ if it contains task_plan.md
#   2. ./.planning/.active_plan content → matching dir if it contains task_plan.md
#   3. Newest ./.planning/<dir>/ by mtime
#   4. ./.state/ if it contains task_plan.md (Codex local workspace fallback)
#   5. Otherwise empty stdout (caller falls back to legacy ./task_plan.md)
#
# Always exits 0. Never errors out the agent loop.
#
# Usage:
#   PLAN_DIR="$(sh scripts/resolve-plan-dir.sh)"
#   PLAN_FILE="${PLAN_DIR:+$PLAN_DIR/}task_plan.md"

set -u

PLAN_ROOT="${1:-${PWD}/.planning}"
ACTIVE_FILE="${PLAN_ROOT}/.active_plan"

valid_plan_id() {
    case "$1" in
        ""|.*|*/*|*\\*|*..*) return 1 ;;
    esac
    return 0
}

is_plan_dir() {
    [ -d "$1" ] && [ -f "$1/task_plan.md" ]
}

resolve_from_env() {
    plan_id="${PLAN_ID:-}"
    valid_plan_id "${plan_id}" || return 1
    candidate="${PLAN_ROOT}/${plan_id}"
    if is_plan_dir "${candidate}"; then
        printf "%s\n" "${candidate}"
        return 0
    fi
    return 1
}

resolve_from_active_file() {
    [ -f "${ACTIVE_FILE}" ] || return 1
    plan_id="$(tr -d '\r\n' < "${ACTIVE_FILE}")"
    valid_plan_id "${plan_id}" || return 1
    candidate="${PLAN_ROOT}/${plan_id}"
    if is_plan_dir "${candidate}"; then
        printf "%s\n" "${candidate}"
        return 0
    fi
    return 1
}

resolve_latest_dir() {
    [ -d "${PLAN_ROOT}" ] || return 1
    # Portable newest-mtime selector. Avoid `ls -t` BSD/GNU drift.
    # Only consider dirs that contain task_plan.md — skips system dirs like sessions/.
    latest=""
    latest_mtime=0
    for entry in "${PLAN_ROOT}"/*/; do
        [ -d "${entry}" ] || continue
        # Strip trailing slash
        clean="${entry%/}"
        # Skip hidden dirs
        case "$(basename "${clean}")" in
            .*) continue ;;
        esac
        # Skip dirs that are not plan dirs
        [ -f "${clean}/task_plan.md" ] || continue
        mtime="$(date -r "${clean}" +%s 2>/dev/null || stat -c '%Y' "${clean}" 2>/dev/null || echo 0)"
        if [ "${mtime}" -gt "${latest_mtime}" ] 2>/dev/null; then
            latest_mtime="${mtime}"
            latest="${clean}"
        fi
    done
    if [ -n "${latest}" ]; then
        printf "%s\n" "${latest}"
        return 0
    fi
    return 1
}

resolve_state_dir() {
    candidate="${PWD}/.state"
    if [ -f "${candidate}/task_plan.md" ]; then
        printf "%s\n" "${candidate}"
        return 0
    fi
    return 1
}

if resolve_from_env; then exit 0; fi
if resolve_from_active_file; then exit 0; fi
if resolve_latest_dir; then exit 0; fi
if resolve_state_dir; then exit 0; fi
exit 0
