#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
C="${SCRIPTS}/ci/check-platform.sh"
export FAKE_SSM_DIR="${WORK}/ssm" FAKE_LOG="${WORK}/aws.log"
mkdir -p "${FAKE_SSM_DIR}"

echo "== check-platform.sh"
echo '{"schema_version":1}' > "${FAKE_SSM_DIR}/_acme_platform_config"
check "core runs it: passes"                        bash "$C" acme af-south-1 production
rm -f "${FAKE_SSM_DIR}/_acme_platform_config"
out="$(bash "$C" acme af-south-1 staging 2>&1)"; rc=$?
check "no contract: refused"                        test $rc -ne 0
check "and the message says core does not run it"   bash -c "grep -q 'core does not run staging' <<< \"$out\""
check "and how to fix it"                           bash -c "grep -q '.github/environments.json' <<< \"$out\""
finish
