#!/bin/sh
# planning-with-files: resolve active plan directory.
#
# Resolution order:
#   1. $KNOT_PLANNING_TASK_DIR if it contains task_plan.md
#   2. $PLAN_ID env var under Knot scope-aware .state/tasks roots
#   3. Knot .state/tasks/.active_task under actor/user/current workspace roots
#   4. $PLAN_ID env var -> ./.planning/$PLAN_ID/ if it contains task_plan.md
#   5. ./.planning/.active_plan content -> matching dir if it contains task_plan.md
#   6. Newest ./.planning/<dir>/ by mtime
#   7. ./.state/ if it contains task_plan.md (Codex local workspace fallback)
#   8. Otherwise empty stdout (caller falls back to legacy ./task_plan.md)
#
# Always exits 0. Never errors out the agent loop.
#
# Usage:
#   PLAN_DIR="$(sh scripts/resolve-plan-dir.sh)"
#   PLAN_FILE="${PLAN_DIR:+$PLAN_DIR/}task_plan.md"

set -u

PLAN_ROOT="${1:-${PWD}/.planning}"
ACTIVE_FILE="${PLAN_ROOT}/.active_plan"

# Plan-id safe-identifier check. Rejects whitespace, path separators, leading
# dots, and empty strings; accepts the YYYY-MM-DD-<slug> shape from
# init-session.sh as well as legacy hand-created names like "alpha" or
# "feature-foo".
SLUG_RE='^[A-Za-z0-9_][A-Za-z0-9._-]*$'

slug_is_valid() {
    case "$1" in
        '') return 1 ;;
    esac
    printf "%s" "$1" | grep -Eq "${SLUG_RE}"
}

is_plan_dir() {
    [ -d "$1" ] && [ -f "$1/task_plan.md" ]
}

# Portable mtime resolver. Tries GNU stat, BSD stat, BSD/macOS date -r,
# python3, then perl. Returns "0" on full miss so callers can sort.
mtime_of() {
    target="$1"
    out="$(stat -c '%Y' "${target}" 2>/dev/null)"
    if [ -n "${out}" ]; then printf "%s\n" "${out}"; return 0; fi
    out="$(stat -f '%m' "${target}" 2>/dev/null)"
    if [ -n "${out}" ]; then printf "%s\n" "${out}"; return 0; fi
    out="$(date -r "${target}" +%s 2>/dev/null)"
    if [ -n "${out}" ]; then printf "%s\n" "${out}"; return 0; fi
    if command -v python3 >/dev/null 2>&1; then
        out="$(python3 -c "import os,sys;print(int(os.stat(sys.argv[1]).st_mtime))" "${target}" 2>/dev/null)"
        if [ -n "${out}" ]; then printf "%s\n" "${out}"; return 0; fi
    fi
    if command -v python >/dev/null 2>&1; then
        out="$(python -c "import os,sys;print(int(os.stat(sys.argv[1]).st_mtime))" "${target}" 2>/dev/null)"
        if [ -n "${out}" ]; then printf "%s\n" "${out}"; return 0; fi
    fi
    if command -v perl >/dev/null 2>&1; then
        out="$(perl -e 'print((stat shift)[9])' "${target}" 2>/dev/null)"
        if [ -n "${out}" ]; then printf "%s\n" "${out}"; return 0; fi
    fi
    printf "0\n"
}

resolve_from_knot_task_dir() {
    candidate="${KNOT_PLANNING_TASK_DIR:-}"
    if [ -n "${candidate}" ] && is_plan_dir "${candidate}"; then
        printf "%s\n" "${candidate}"
        return 0
    fi
    return 1
}

resolve_plan_id_in_root() {
    root="$1"
    plan_id="$2"
    candidate="${root}/${plan_id}"
    if is_plan_dir "${candidate}"; then
        printf "%s\n" "${candidate}"
        return 0
    fi
    return 1
}

resolve_from_knot_plan_id() {
    plan_id="${PLAN_ID:-}"
    slug_is_valid "${plan_id}" || return 1
    if [ -n "${KNOT_ACTOR_WORKSPACE:-}" ] && resolve_plan_id_in_root "${KNOT_ACTOR_WORKSPACE}/.state/tasks" "${plan_id}"; then return 0; fi
    if [ -n "${KNOT_USER_WORKSPACE:-}" ] && resolve_plan_id_in_root "${KNOT_USER_WORKSPACE}/.state/tasks" "${plan_id}"; then return 0; fi
    if [ -n "${KNOT_ACTIVE_WORKSPACE:-}" ] && resolve_plan_id_in_root "${KNOT_ACTIVE_WORKSPACE}/.state/tasks" "${plan_id}"; then return 0; fi
    if [ -n "${KNOT_ROOT:-}" ] && resolve_plan_id_in_root "${KNOT_ROOT}/workspace/.state/tasks" "${plan_id}"; then return 0; fi
    if resolve_plan_id_in_root "${PWD}/workspace/.state/tasks" "${plan_id}"; then return 0; fi
    resolve_plan_id_in_root "${PWD}/.state/tasks" "${plan_id}" && return 0
    return 1
}

resolve_active_in_root() {
    root="$1"
    active="${root}/.active_task"
    [ -f "${active}" ] || return 1
    plan_id="$(tr -d '\r\n[:space:]' < "${active}")"
    slug_is_valid "${plan_id}" || return 1
    resolve_plan_id_in_root "${root}" "${plan_id}"
}

resolve_from_knot_active_file() {
    if [ -n "${KNOT_ACTOR_WORKSPACE:-}" ] && resolve_active_in_root "${KNOT_ACTOR_WORKSPACE}/.state/tasks"; then return 0; fi
    if [ -n "${KNOT_USER_WORKSPACE:-}" ] && resolve_active_in_root "${KNOT_USER_WORKSPACE}/.state/tasks"; then return 0; fi
    if [ -n "${KNOT_ACTIVE_WORKSPACE:-}" ] && resolve_active_in_root "${KNOT_ACTIVE_WORKSPACE}/.state/tasks"; then return 0; fi
    if [ -n "${KNOT_ROOT:-}" ] && resolve_active_in_root "${KNOT_ROOT}/workspace/.state/tasks"; then return 0; fi
    if resolve_active_in_root "${PWD}/workspace/.state/tasks"; then return 0; fi
    resolve_active_in_root "${PWD}/.state/tasks" && return 0
    return 1
}

resolve_from_env() {
    plan_id="${PLAN_ID:-}"
    slug_is_valid "${plan_id}" || return 1
    candidate="${PLAN_ROOT}/${plan_id}"
    if is_plan_dir "${candidate}"; then
        printf "%s\n" "${candidate}"
        return 0
    fi
    return 1
}

resolve_from_active_file() {
    [ -f "${ACTIVE_FILE}" ] || return 1
    plan_id="$(tr -d '\r\n[:space:]' < "${ACTIVE_FILE}")"
    slug_is_valid "${plan_id}" || return 1
    candidate="${PLAN_ROOT}/${plan_id}"
    if is_plan_dir "${candidate}"; then
        printf "%s\n" "${candidate}"
        return 0
    fi
    return 1
}

resolve_latest_dir() {
    [ -d "${PLAN_ROOT}" ] || return 1
    # Portable newest-mtime selector. Skips hidden dirs, slug-invalid names,
    # and dirs without task_plan.md (e.g. sessions/).
    latest=""
    latest_mtime=0
    for entry in "${PLAN_ROOT}"/*/; do
        [ -d "${entry}" ] || continue
        clean="${entry%/}"
        name="$(basename "${clean}")"
        case "${name}" in
            .*) continue ;;
        esac
        slug_is_valid "${name}" || continue
        [ -f "${clean}/task_plan.md" ] || continue
        mtime="$(mtime_of "${clean}")"
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
    if is_plan_dir "${candidate}"; then
        printf "%s\n" "${candidate}"
        return 0
    fi
    return 1
}

if resolve_from_knot_task_dir; then exit 0; fi
if resolve_from_knot_plan_id; then exit 0; fi
if resolve_from_knot_active_file; then exit 0; fi
if resolve_from_env; then exit 0; fi
if resolve_from_active_file; then exit 0; fi
if resolve_latest_dir; then exit 0; fi
if resolve_state_dir; then exit 0; fi
exit 0
