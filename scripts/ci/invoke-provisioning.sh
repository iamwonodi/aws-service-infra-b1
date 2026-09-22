#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# CREATE THIS SERVICE'S DATABASE AND USER ON A MANAGED DATABASE
#
# A managed database has no host to send an SSM document to, so core runs a
# Lambda inside the VPC that does the same job. This invokes it and fails the
# workflow if it fails.
#
# The payload names ONLY the service. The function derives the secret's name from
# its own convention, so this repository cannot point it at another service's
# credential, and it runs no SQL this repository supplies.
#
# It is invoked AFTER the apply, and on every apply. Core's provisioning is
# conditional throughout and sets the password each time, so repeating it is
# harmless -- and a rotated secret heals itself on the next apply.
#
# A Lambda that raises still returns HTTP 200: the failure is in the response's
# FunctionError field and in the payload, not in the exit status of the CLI. So
# both are checked here; relying on the exit status alone would report success.
#
# Usage: invoke-provisioning.sh <function-name> <service> <aws-region>
# ==============================================================================

FUNCTION="${1:?Usage: invoke-provisioning.sh <function-name> <service> <aws-region>}"
SERVICE="${2:?service is required}"
REGION="${3:?aws-region is required}"

[[ "${FUNCTION}" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || { echo "ERROR: '${FUNCTION}' is not a Lambda function name." >&2; exit 1; }
[[ "${SERVICE}" =~ ^[a-z][a-z0-9-]{1,20}[a-z0-9]$ ]] || { echo "ERROR: '${SERVICE}' is not a service name." >&2; exit 1; }

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "${RESPONSE_FILE}"' EXIT

PAYLOAD="$(jq -cn --arg s "${SERVICE}" '{service_name: $s}')"

echo "Provisioning the database for '${SERVICE}' (function ${FUNCTION})."

if ! METADATA="$(aws lambda invoke \
    --function-name "${FUNCTION}" \
    --payload "${PAYLOAD}" \
    --cli-binary-format raw-in-base64-out \
    --log-type Tail \
    --region "${REGION}" \
    --output json \
    "${RESPONSE_FILE}" 2>&1)"; then
  echo "ERROR: could not invoke ${FUNCTION}: ${METADATA}" >&2
  exit 1
fi

# The function's own log tail, base64-encoded, so a failure shows its cause here.
LOG="$(jq -r '.LogResult // empty' <<< "${METADATA}" | base64 -d 2>/dev/null || true)"
if [[ -n "${LOG}" ]]; then
  echo "--- function log"
  sed 's/^/    /' <<< "${LOG}"
fi

FUNCTION_ERROR="$(jq -r '.FunctionError // empty' <<< "${METADATA}")"

if [[ -n "${FUNCTION_ERROR}" ]]; then
  echo "ERROR: provisioning '${SERVICE}' failed (${FUNCTION_ERROR}):" >&2
  jq -r '.errorMessage // .' "${RESPONSE_FILE}" 2>/dev/null | sed 's/^/       /' >&2 || cat "${RESPONSE_FILE}" >&2
  exit 1
fi

STATUS="$(jq -r '.status // empty' "${RESPONSE_FILE}" 2>/dev/null || true)"

if [[ "${STATUS}" != "provisioned" ]]; then
  echo "ERROR: the function returned no 'provisioned' status for '${SERVICE}':" >&2
  sed 's/^/       /' "${RESPONSE_FILE}" >&2
  exit 1
fi

echo "The database and user for '${SERVICE}' are in place."
