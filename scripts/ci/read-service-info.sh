#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# READ THE SERVICE'S IDENTITY FROM AN ENVIRONMENT'S terraform.tfvars
#
# The port registry and the database provisioning need the project and the
# service's name, type, tier and port, which the workflows must take from what
# will actually be applied, never from separate configuration that could disagree. Prints KEY=VALUE lines for GITHUB_ENV.
#
# Usage: read-service-info.sh <environment-dir>
# ==============================================================================

DIR="${1:?Usage: read-service-info.sh <environment-dir>}"
FILE="${DIR}/terraform.tfvars"

[[ -f "${FILE}" ]] || { echo "ERROR: ${FILE} not found." >&2; exit 1; }

read_value() {
  local key="$1" value

  value="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\{0,1\}\([^\"# ]*\)\"\{0,1\}.*/\1/p" "${FILE}" | head -n 1)"

  [[ -n "${value}" ]] || { echo "ERROR: '${key}' not found (or empty) in ${FILE}." >&2; exit 1; }

  echo "${value}"
}

PROJECT_NAME="$(read_value project_name)"
SERVICE_NAME="$(read_value service_name)"
SERVICE_TYPE="$(read_value service_type)"
SERVICE_TIER="$(read_value tier)"
SERVICE_PORT="$(read_value service_port)"

[[ "${PROJECT_NAME}" =~ ^[a-z][a-z0-9-]{1,14}[a-z0-9]$ ]] || { echo "ERROR: project_name '${PROJECT_NAME}' is not valid." >&2; exit 1; }
[[ "${SERVICE_NAME}" =~ ^[a-z][a-z0-9-]{1,20}[a-z0-9]$ ]] || { echo "ERROR: service_name '${SERVICE_NAME}' is not valid." >&2; exit 1; }
[[ "${SERVICE_TYPE}" =~ ^[a-z][a-z0-9-]{0,15}$ ]] || { echo "ERROR: service_type '${SERVICE_TYPE}' is not valid." >&2; exit 1; }
[[ "${SERVICE_TIER}" == "private" || "${SERVICE_TIER}" == "internal" ]] || { echo "ERROR: tier '${SERVICE_TIER}' must be private or internal." >&2; exit 1; }
[[ "${SERVICE_PORT}" =~ ^[0-9]+$ && "${SERVICE_PORT}" -ge 1024 && "${SERVICE_PORT}" -le 65535 ]] || { echo "ERROR: service_port '${SERVICE_PORT}' must be 1024-65535." >&2; exit 1; }

echo "PROJECT_NAME=${PROJECT_NAME}"
echo "SERVICE_NAME=${SERVICE_NAME}"
echo "SERVICE_TYPE=${SERVICE_TYPE}"
echo "SERVICE_TIER=${SERVICE_TIER}"
echo "SERVICE_PORT=${SERVICE_PORT}"
