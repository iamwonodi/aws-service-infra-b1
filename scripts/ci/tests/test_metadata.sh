#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
C="${SCRIPTS}/ci/create-deployment-metadata.sh"
R="${SCRIPTS}/ci/read-deployment-metadata.sh"
D="${SCRIPTS}/ci/discover-environments-from-artifacts.sh"
SHA="0123456789abcdef0123456789abcdef01234567"
mkdir -p "${WORK}/d"

echo "== deployment metadata"
bash "$C" "${WORK}/d" development "$SHA" >/dev/null 2>&1
check "the file is valid JSON"                    jq -e . "${WORK}/d/deployment-metadata.json"
bash "$R" "${WORK}/d/deployment-metadata.json" > "${WORK}/read.out" 2>&1
check "read gives the SHA and environment"        bash -c "grep -qx 'INFRASTRUCTURE_SHA=$SHA' '${WORK}/read.out' && grep -qx 'ENVIRONMENT=development' '${WORK}/read.out'"
check "output is safe to append to GITHUB_ENV"    bash -c "! grep -vE '^[A-Z_]+=' '${WORK}/read.out'"
check "bad SHA rejected"                          bash -c "! bash '$C' '${WORK}/d' development notasha >/dev/null 2>&1"
check "unknown environment rejected"              bash -c "! bash '$C' '${WORK}/d' prod '$SHA' >/dev/null 2>&1"
check "wrong argument count rejected"             bash -c "! bash '$C' '${WORK}/d' development >/dev/null 2>&1"
printf '{"infrastructure_sha":"%s"}' "$SHA" > "${WORK}/noenv.json"
check "read rejects a missing environment"        bash -c "! bash '$R' '${WORK}/noenv.json' >/dev/null 2>&1"
printf '{"infrastructure_sha":"%s","environment":""}' "$SHA" > "${WORK}/emptyenv.json"
check "read rejects an empty environment"         bash -c "! bash '$R' '${WORK}/emptyenv.json' >/dev/null 2>&1"
check "read rejects a missing file"               bash -c "! bash '$R' '${WORK}/none.json' >/dev/null 2>&1"

echo "== discover environments from plan artifacts"
mkdir -p "${WORK}/art/tfplan-development-1"
bash "$C" "${WORK}/art/tfplan-development-1" development "$SHA" >/dev/null
check "one artifact -> that environment"          test "$(bash "$D" "${WORK}/art")" = '["development"]'
check "no artifacts is an error"                  bash -c "! bash '$D' '${WORK}/d/empty' >/dev/null 2>&1"
finish
