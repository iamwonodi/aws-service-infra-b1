#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
P="${SCRIPTS}/ci/invoke-provisioning.sh"
export FAKE_LOG="${WORK}/aws.log"
run(){ bash "$P" core-production-postgres-provision auth af-south-1; }

echo "== invoke-provisioning.sh"
: > "${FAKE_LOG}"
out="$(run 2>&1)"; rc=$?
check "succeeds when the function reports provisioned"  test $rc -eq 0
check "invokes core's function"                          grep -q 'lambda invoke --function-name core-production-postgres-provision' "${FAKE_LOG}"
check "the payload names the service and nothing else"  grep -q -- '--payload {"service_name":"auth"}' "${FAKE_LOG}"
check "the function's log is shown"                      bash -c "grep -q 'Provisioned auth' <<< \"$out\""

out="$(FAKE_LAMBDA_FUNCTION_ERROR='could not connect to db:5432' bash "$P" f auth r 2>&1)"; rc=$?
check "a function that RAISED fails the workflow (HTTP 200 notwithstanding)" test $rc -ne 0
check "and its error message is shown"                   bash -c "grep -q 'could not connect to db:5432' <<< \"$out\""
check "a function that could not be invoked fails"       bash -c "! FAKE_LAMBDA_FAIL=1 bash '$P' f auth r >/dev/null 2>&1"
check "a response without 'provisioned' fails"           bash -c "! FAKE_LAMBDA_RESPONSE='{\"status\":\"skipped\"}' bash '$P' f auth r >/dev/null 2>&1"
check "a response that is not JSON fails"                bash -c "! FAKE_LAMBDA_RESPONSE='oops' bash '$P' f auth r >/dev/null 2>&1"
check "a bad service name is refused"                    bash -c "! bash '$P' f 'Bad Name' r >/dev/null 2>&1"
check "a bad function name is refused"                   bash -c "! bash '$P' 'f; rm -rf /' auth r >/dev/null 2>&1"
check "missing arguments are refused"                    bash -c "! bash '$P' f >/dev/null 2>&1"
finish
