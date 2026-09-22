#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# CREATE THIS SERVICE'S DATABASE AND USER, AND WAIT FOR THE RESULT
#
# Terraform published the provisioning request; this sends core's provisioning
# document to the database host and follows it until it finishes. Core's script
# creates the database, the user, its password and its grants from the secret
# this repository generated.
#
# It is sent AFTER the apply, and on every apply. Core's provisioning is
# conditional throughout and sets the password each time, so running it again is
# harmless -- and a rotated secret heals itself on the next apply.
#
# The document is the only thing this repository's role may send to that host, so
# this is not permission to run commands there.
#
# A failed provisioning fails the workflow: a service whose database was never
# created would otherwise deploy and then fail to connect, with nothing in CI to
# say why.
#
# Usage: provision-database.sh <document> <project> <service> <aws-region>
#
# Environment (all optional):
#   PROVISION_INTERVAL     seconds between checks                     (default 5)
#   PROVISION_TIMEOUT      seconds to wait for it to finish           (default 600)
#   PROVISION_EMPTY_GRACE  seconds to wait for the host to answer     (default 60)
# ==============================================================================

DOCUMENT="${1:?Usage: provision-database.sh <document> <project> <service> <aws-region>}"
PROJECT="${2:?project is required}"
SERVICE="${3:?service is required}"
REGION="${4:?aws-region is required}"

INTERVAL="${PROVISION_INTERVAL:-5}"
TIMEOUT="${PROVISION_TIMEOUT:-600}"
EMPTY_GRACE="${PROVISION_EMPTY_GRACE:-60}"

[[ "${DOCUMENT}" =~ ^[A-Za-z0-9_.-]{3,128}$ ]] || { echo "ERROR: '${DOCUMENT}' is not a document name." >&2; exit 1; }
[[ "${SERVICE}" =~ ^[a-z][a-z0-9-]{1,20}[a-z0-9]$ ]] || { echo "ERROR: '${SERVICE}' is not a service name." >&2; exit 1; }

# The database host, not the fleet: core tags it with its own service name, and
# the role may send this document only to an instance carrying it.
DATABASE_SERVICE="${DATABASE_SERVICE_TAG:-database-hub}"

echo "Provisioning the database for '${SERVICE}' (document ${DOCUMENT})."

if ! COMMAND_ID="$(aws ssm send-command \
    --document-name "${DOCUMENT}" \
    --targets "Key=tag:Project,Values=${PROJECT}" "Key=tag:Service,Values=${DATABASE_SERVICE}" \
    --parameters "serviceName=${SERVICE}" \
    --comment "Provision ${SERVICE}" \
    --query "Command.CommandId" --output text \
    --region "${REGION}" 2>&1)"; then
  echo "ERROR: could not send the provisioning command: ${COMMAND_ID}" >&2
  exit 1
fi

echo "Command ${COMMAND_ID} sent. Waiting for the database host."

START="${SECONDS}"

while true; do

  INVOCATIONS="$(aws ssm list-command-invocations \
    --command-id "${COMMAND_ID}" --details \
    --query "CommandInvocations[].{id:InstanceId,status:Status,out:CommandPlugins[0].Output}" \
    --output json --region "${REGION}")"

  COUNT="$(jq 'length' <<< "${INVOCATIONS}")"
  ELAPSED=$(( SECONDS - START ))

  if [[ "${COUNT}" -eq 0 ]]; then
    if [[ ${ELAPSED} -ge ${EMPTY_GRACE} ]]; then
      echo "ERROR: the database host did not answer. Is there a running instance tagged Project=${PROJECT} and Service=${DATABASE_SERVICE}?" >&2
      exit 1
    fi
  else
    BUSY="$(jq '[.[] | select(.status == "Pending" or .status == "InProgress" or .status == "Delayed")] | length' <<< "${INVOCATIONS}")"
    [[ "${BUSY}" -eq 0 ]] && break
    echo "  still provisioning (${ELAPSED}s)."
  fi

  if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
    echo "ERROR: provisioning had not finished after ${TIMEOUT}s; giving up waiting." >&2
    exit 1
  fi

  sleep "${INTERVAL}"

done

FAILED=0

while IFS= read -r invocation; do
  ID="$(jq -r '.id' <<< "${invocation}")"
  STATUS="$(jq -r '.status' <<< "${invocation}")"

  echo
  echo "--- ${ID}: ${STATUS}"
  jq -r '.out // "" | split("\n") | .[-25:] | .[]' <<< "${invocation}" | sed 's/^/    /'

  [[ "${STATUS}" == "Success" ]] || FAILED=$(( FAILED + 1 ))
done < <(jq -c '.[]' <<< "${INVOCATIONS}")

echo

if [[ ${FAILED} -gt 0 ]]; then
  echo "ERROR: provisioning '${SERVICE}' did not succeed." >&2
  exit 1
fi

echo "The database and user for '${SERVICE}' are in place."
