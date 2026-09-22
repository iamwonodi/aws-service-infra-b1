#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# THE SERVICE REGISTRY: NAMES AND PORTS, CLAIMED ONCE
#
# Services on the shared fleet share a host, so two services must never use the
# same host port on a tier, and a service name must belong to one repository. A
# small registry repository records both. This script checks a claim and, after a
# successful apply, makes it.
#
#   check   read-only. Safe on a pull request: an abandoned PR claims nothing.
#   claim   writes the entry and pushes it. Run it only after the change is applied.
#
# Registry layout (the registry repository is checked out by the workflow):
#
#   development/private-service-registry.json     port checked within a tier
#   development/internal-service-registry.json
#   staging/service-registry.json                 names only
#   production/service-registry.json              names only
#
# Each file is {"<service>": {"port": N, "service_type": "...", "repository": "OWNER/REPO"}}.
#
# Rules:
#   - a service name belongs to one repository, for good;
#   - in development a port belongs to one service per tier;
#   - PROMOTION GATE: a service may first appear in staging only if this repository
#     registered it in development, and in production only if it is in staging
#     (or development). A routine update to an already-registered service skips it.
#
# claim retries after rebasing when another service claimed at the same moment,
# and re-checks every time, so two services can never both win the same port.
#
# Usage:
#   port-registry.sh check|claim --registry-dir DIR --environment ENV [--tier TIER] \
#       --service NAME --type TYPE --port N --repo OWNER/REPO
#
# Environment: REGISTRY_MAX_ATTEMPTS (default 5)
# ==============================================================================

ACTION="${1:-}"
shift || true

REGISTRY_DIR="" ENVIRONMENT="" TIER="" SERVICE="" TYPE="" PORT="" REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry-dir) REGISTRY_DIR="${2:-}"; shift 2 ;;
    --environment)  ENVIRONMENT="${2:-}"; shift 2 ;;
    --tier)         TIER="${2:-}"; shift 2 ;;
    --service)      SERVICE="${2:-}"; shift 2 ;;
    --type)         TYPE="${2:-}"; shift 2 ;;
    --port)         PORT="${2:-}"; shift 2 ;;
    --repo)         REPO="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown argument '$1'." >&2; exit 1 ;;
  esac
done

case "${ACTION}" in
  check|claim) ;;
  *) echo "ERROR: first argument must be check or claim." >&2; exit 1 ;;
esac

MAX_ATTEMPTS="${REGISTRY_MAX_ATTEMPTS:-5}"

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------
fail() { echo "ERROR: $*" >&2; exit 1; }

[[ -d "${REGISTRY_DIR}" ]] || fail "--registry-dir must be an existing directory."
[[ "${SERVICE}" =~ ^[a-z][a-z0-9-]{1,20}[a-z0-9]$ ]] || fail "--service '${SERVICE}' is not a valid service name."
[[ "${TYPE}" =~ ^[a-z][a-z0-9-]{0,15}$ ]] || fail "--type '${TYPE}' is not a valid service type."
[[ "${PORT}" =~ ^[0-9]+$ && "${PORT}" -ge 1024 && "${PORT}" -le 65535 ]] || fail "--port '${PORT}' must be a whole number from 1024 to 65535."
[[ "${REPO}" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || fail "--repo '${REPO}' must be OWNER/REPOSITORY."

case "${ENVIRONMENT}" in
  development)
    [[ "${TIER}" == "private" || "${TIER}" == "internal" ]] || fail "--tier must be private or internal in development."
    REGISTRY_FILE="${REGISTRY_DIR}/development/${TIER}-service-registry.json"
    CHECK_PORT=true
    LOWER=()
    ;;
  staging)
    REGISTRY_FILE="${REGISTRY_DIR}/staging/service-registry.json"
    CHECK_PORT=false
    LOWER=("${REGISTRY_DIR}/development/private-service-registry.json" "${REGISTRY_DIR}/development/internal-service-registry.json")
    ;;
  production)
    REGISTRY_FILE="${REGISTRY_DIR}/production/service-registry.json"
    CHECK_PORT=false
    LOWER=("${REGISTRY_DIR}/staging/service-registry.json" "${REGISTRY_DIR}/development/private-service-registry.json" "${REGISTRY_DIR}/development/internal-service-registry.json")
    ;;
  *) fail "unknown environment '${ENVIRONMENT}'." ;;
esac

read_registry() {
  # Prints the file's JSON, or {} when it does not exist yet.
  if [[ -f "$1" ]]; then
    jq -e 'if type == "object" then . else error("not an object") end' "$1" 2>/dev/null || fail "$1 is not a JSON object."
  else
    echo '{}'
  fi
}

# ------------------------------------------------------------------------------
# The rules. Exits non-zero, naming the cause, when a claim would be refused.
# ------------------------------------------------------------------------------
check_claim() {
  local registry existing_repo conflicting lower lower_repo

  registry="$(read_registry "${REGISTRY_FILE}")"

  existing_repo="$(jq -r --arg n "${SERVICE}" '.[$n].repository // empty' <<< "${registry}")"

  if [[ -n "${existing_repo}" && "${existing_repo}" != "${REPO}" ]]; then
    fail "service '${SERVICE}' is already claimed by a different repository: ${existing_repo}."
  fi

  if [[ "${CHECK_PORT}" == "true" ]]; then
    conflicting="$(jq -r --arg n "${SERVICE}" --arg p "${PORT}" \
      'to_entries[] | select(.key != $n and (.value.port | tostring) == $p) | .key' <<< "${registry}" | head -n 1)"

    if [[ -n "${conflicting}" ]]; then
      fail "port ${PORT} is already used by service '${conflicting}' on the ${TIER} tier."
    fi
  fi

  # Promotion gate: only for a service not yet registered in this environment.
  if [[ ${#LOWER[@]} -gt 0 && -z "${existing_repo}" ]]; then
    for lower in "${LOWER[@]}"; do
      [[ -f "${lower}" ]] || continue
      lower_repo="$(jq -r --arg n "${SERVICE}" '.[$n].repository // empty' "${lower}")"
      if [[ "${lower_repo}" == "${REPO}" ]]; then
        echo "Promotion allowed: ${REPO} registered '${SERVICE}' in ${lower#"${REGISTRY_DIR}"/}."
        return 0
      fi
    done

    fail "'${SERVICE}' has not been registered by ${REPO} in a lower environment, so it cannot first appear in ${ENVIRONMENT}."
  fi

  if [[ "${CHECK_PORT}" == "true" ]]; then
    echo "Claim for '${SERVICE}' on port ${PORT} (${TIER} tier) is valid."
  else
    echo "Claim for '${SERVICE}' is valid."
  fi
}

# ------------------------------------------------------------------------------
# claim: write, commit, push -- and start again from the newest registry if the
# push is rejected because someone else claimed first.
# ------------------------------------------------------------------------------
write_entry() {
  local registry
  registry="$(read_registry "${REGISTRY_FILE}")"
  mkdir -p "$(dirname "${REGISTRY_FILE}")"
  jq --arg n "${SERVICE}" --arg t "${TYPE}" --argjson p "${PORT}" --arg r "${REPO}" \
    '.[$n] = {port: $p, service_type: $t, repository: $r}' <<< "${registry}" > "${REGISTRY_FILE}.tmp"
  mv "${REGISTRY_FILE}.tmp" "${REGISTRY_FILE}"
}

if [[ "${ACTION}" == "check" ]]; then
  check_claim
  exit 0
fi

git -C "${REGISTRY_DIR}" config --get user.name >/dev/null 2>&1 || git -C "${REGISTRY_DIR}" config user.name "github-actions[bot]"
git -C "${REGISTRY_DIR}" config --get user.email >/dev/null 2>&1 || git -C "${REGISTRY_DIR}" config user.email "github-actions[bot]@users.noreply.github.com"

for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do

  check_claim
  write_entry

  git -C "${REGISTRY_DIR}" add -A

  if git -C "${REGISTRY_DIR}" diff --cached --quiet; then
    echo "The registry already holds exactly this claim."
    exit 0
  fi

  git -C "${REGISTRY_DIR}" commit --quiet -m "Register ${SERVICE} on port ${PORT} (${REPO})"

  if git -C "${REGISTRY_DIR}" push --quiet; then
    echo "Claimed '${SERVICE}' on port ${PORT} (attempt ${attempt})."
    exit 0
  fi

  if [[ ${attempt} -eq ${MAX_ATTEMPTS} ]]; then
    fail "could not push the claim after ${MAX_ATTEMPTS} attempts."
  fi

  echo "Push rejected (attempt ${attempt}); taking the newest registry and checking the claim again."

  # Throw away our commit and start from what is on the remote now: the rules are
  # then evaluated against it, so a port taken in the meantime is caught.
  git -C "${REGISTRY_DIR}" fetch --quiet origin
  git -C "${REGISTRY_DIR}" reset --quiet --hard "@{upstream}"
  sleep "$(( (RANDOM % 3) + 1 ))"

done
