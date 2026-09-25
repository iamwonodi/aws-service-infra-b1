#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# DOES CORE RUN THIS ENVIRONMENT?
#
# A service lives on core's platform: it can run only in environments core runs.
# Core publishes its platform contract, /<project>/platform/config, in every
# account it runs, so its absence means core does not run this environment (or
# has not been applied there yet). Checked before Terraform, which would fail
# with a bare "parameter not found".
#
# Usage: check-platform.sh <project> <aws-region> <environment>
# ==============================================================================

PROJECT="${1:?Usage: check-platform.sh <project> <aws-region> <environment>}"
REGION="${2:?aws-region is required}"
ENVIRONMENT="${3:?environment is required}"
PARAMETER="/${PROJECT}/platform/config"

if ! ERROR="$(aws ssm get-parameter --region "${REGION}" --name "${PARAMETER}" --query 'Parameter.Name' --output text 2>&1 >/dev/null)"; then
  if grep -q "ParameterNotFound" <<< "${ERROR}"; then
    echo "ERROR: core's platform contract (${PARAMETER}) does not exist in ${ENVIRONMENT}'s account." >&2
    echo "       A service can run only where core runs: either core does not run ${ENVIRONMENT}" >&2
    echo "       (its environments.json), or it has not been applied there yet. Remove ${ENVIRONMENT}" >&2
    echo "       from .github/environments.json, or apply core's ${ENVIRONMENT} first." >&2
  else
    echo "ERROR: could not read ${PARAMETER} in ${ENVIRONMENT}: ${ERROR}" >&2
  fi
  exit 1
fi

echo "Core runs ${ENVIRONMENT}: its platform contract is there."
