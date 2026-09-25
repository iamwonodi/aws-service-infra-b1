#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# WHICH ENVIRONMENTS SHOULD A WORKFLOW RUN FOR?
#
# Only environments listed in .github/environments.json are ever planned or
# applied. Staging and production stay off that list until this blueprint hosts
# services there, so a change to shared code never makes CI plan an environment
# that cannot yet be planned.
#
#   pull_request        every enabled environment when shared code changed
#                       (modules/, scripts/ are ignored; modules/ and the
#                       Terraform version are not), otherwise only the
#                       environments whose own folder changed
#   workflow_dispatch   exactly the requested environment, if it is enabled
#
# Prints a compact JSON array, e.g. ["development"]; "[]" means nothing to do.
#
# Usage:
#   resolve-environments.sh pull_request <base-sha> <head-sha>
#   resolve-environments.sh workflow_dispatch <environment>
# ==============================================================================

ROOT="${RESOLVE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ENABLED_FILE="${ROOT}/.github/environments.json"

# Checked (known names, none twice, not empty) and in the platform's order.
ENABLED="$(ENVIRONMENTS_FILE="${ENABLED_FILE}" bash "$(dirname "${BASH_SOURCE[0]}")/enabled-environments.sh")"

EVENT="${1:-}"

case "${EVENT}" in

  workflow_dispatch)
    REQUESTED="${2:-}"

    if [[ -z "${REQUESTED}" ]]; then
      echo "ERROR: workflow_dispatch needs an environment." >&2
      exit 1
    fi

    if jq -e --arg e "${REQUESTED}" 'index($e) != null' <<< "${ENABLED}" >/dev/null; then
      jq -cn --arg e "${REQUESTED}" '[$e]'
    else
      echo "ERROR: '${REQUESTED}' is not enabled. Enabled environments: $(jq -r 'join(", ")' <<< "${ENABLED}")." >&2
      exit 1
    fi
    ;;

  pull_request)
    BASE="${2:-}"
    HEAD="${3:-}"

    if [[ -z "${BASE}" || -z "${HEAD}" ]]; then
      echo "ERROR: pull_request needs <base-sha> <head-sha>." >&2
      exit 1
    fi

    CHANGED="$(git -C "${ROOT}" diff --name-only "${BASE}...${HEAD}")"

    SHARED=false
    if grep -qE '^(modules/|\.terraform-version$)' <<< "${CHANGED}"; then
      SHARED=true
    fi

    RESULT="[]"
    for ENV in $(jq -r '.[]' <<< "${ENABLED}"); do
      if [[ "${SHARED}" == "true" ]] || grep -q "^infrastructure/${ENV}/" <<< "${CHANGED}"; then
        RESULT="$(jq -c --arg e "${ENV}" '. + [$e]' <<< "${RESULT}")"
      fi
    done

    echo "${RESULT}"
    ;;

  *)
    echo "ERROR: Usage: ${0} pull_request <base> <head> | workflow_dispatch <environment>" >&2
    exit 1
    ;;
esac
