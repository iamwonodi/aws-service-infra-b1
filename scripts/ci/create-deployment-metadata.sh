#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# RECORD WHAT PRODUCED A PLAN
#
# terraform-apply.yml reads this back to check out the exact commit the plan was
# generated from and to learn which environment it belongs to. jq builds the JSON
# so no value can break out of a string.
#
# Usage: create-deployment-metadata.sh <environment-dir> <environment> <infrastructure-sha>
# ==============================================================================

if [[ $# -ne 3 ]]; then
  echo "ERROR: Usage: ${0} <environment-dir> <environment> <infrastructure-sha>" >&2
  exit 1
fi

ENV_DIR="$1"
ENVIRONMENT="$2"
INFRASTRUCTURE_SHA="$3"

case "${ENVIRONMENT}" in
  development|staging|production) ;;
  *)
    echo "ERROR: unknown environment '${ENVIRONMENT}'." >&2
    exit 1
    ;;
esac

if ! [[ "${INFRASTRUCTURE_SHA}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "ERROR: '${INFRASTRUCTURE_SHA}' is not a full 40-character commit SHA." >&2
  exit 1
fi

jq -n \
  --arg sha "${INFRASTRUCTURE_SHA}" \
  --arg env "${ENVIRONMENT}" \
  '{infrastructure_sha: $sha, environment: $env}' > "${ENV_DIR}/deployment-metadata.json"

cat "${ENV_DIR}/deployment-metadata.json"
