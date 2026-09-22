#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# READ A PLAN'S METADATA
#
# Prints KEY=VALUE lines suitable for appending to GITHUB_ENV. Both fields are
# required: an apply must know exactly which commit and environment its plan was
# made for.
#
# Usage: read-deployment-metadata.sh <metadata-json-file>
# ==============================================================================

if [[ $# -ne 1 ]]; then
  echo "ERROR: Usage: ${0} <metadata-json-file>" >&2
  exit 1
fi

FILE="$1"

if [[ ! -s "${FILE}" ]]; then
  echo "ERROR: metadata file not found or empty: ${FILE}" >&2
  exit 1
fi

for FIELD in infrastructure_sha environment; do
  if ! jq -e --arg f "${FIELD}" 'has($f) and (.[$f] | type == "string" and length > 0)' "${FILE}" >/dev/null 2>&1; then
    echo "ERROR: ${FILE} is missing required field '${FIELD}'." >&2
    exit 1
  fi
done

jq -r '"INFRASTRUCTURE_SHA=" + .infrastructure_sha, "ENVIRONMENT=" + .environment' "${FILE}"
