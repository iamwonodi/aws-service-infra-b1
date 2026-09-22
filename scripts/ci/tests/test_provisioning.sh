#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
P="${SCRIPTS}/ci/provision-database.sh"
export FAKE_LOG="${WORK}/aws.log" PROVISION_INTERVAL=0 PROVISION_TIMEOUT=30 PROVISION_EMPTY_GRACE=30

seq_dir(){ rm -rf "${WORK}/inv"; mkdir -p "${WORK}/inv"; export FAKE_INVOCATIONS_DIR="${WORK}/inv"; : > "${FAKE_LOG}"; }
inv(){ printf '%s' "$2" > "${WORK}/inv/$1.json"; }
run(){ bash "$P" core-database-provision acme auth eu-west-1; }
OK='[{"id":"i-db","status":"Success","out":"Provisioned '"'"'auth'"'"'."}]'

echo "== provision-database.sh"
seq_dir; inv 1 "$OK"
out="$(run 2>&1)"; rc=$?
check "succeeds when the host reports Success"          test $rc -eq 0
check "sends core's provisioning document"              grep -q -- '--document-name core-database-provision' "${FAKE_LOG}"
check "to the DATABASE host, not the fleet"             grep -q -- '--targets Key=tag:Project,Values=acme Key=tag:Service,Values=database-hub' "${FAKE_LOG}"
check "naming this service"                             grep -q -- '--parameters serviceName=auth' "${FAKE_LOG}"
check "never AWS-RunShellScript"                        bash -c "! grep -q 'RunShellScript' '${FAKE_LOG}'"
check "the host's output is shown"                      bash -c "grep -q \"Provisioned\" <<< \"$out\""

seq_dir; inv 1 '[{"id":"i-db","status":"InProgress","out":""}]'; inv 2 "$OK"
run >/dev/null 2>&1
check "waits while it is still running"                 test $? -eq 0
check "it polled more than once"                        bash -c "[ \"\$(grep -c 'list-command-invocations' '${FAKE_LOG}')\" -ge 2 ]"

seq_dir; inv 1 '[{"id":"i-db","status":"Failed","out":"ERROR: no provisioning request"}]'
out="$(run 2>&1)"; rc=$?
check "a failed provisioning fails the workflow"        test $rc -ne 0
check "and the reason is shown"                         bash -c "grep -q 'no provisioning request' <<< \"$out\""
seq_dir; inv 1 '[]'
check "no database host answering fails"                bash -c "! PROVISION_EMPTY_GRACE=1 PROVISION_INTERVAL=1 bash '$P' d acme auth r >/dev/null 2>&1"
seq_dir; inv 1 '[{"id":"i-db","status":"InProgress","out":""}]'
check "a host that never finishes fails after the timeout" bash -c "! PROVISION_TIMEOUT=1 PROVISION_INTERVAL=1 bash '$P' core-database-provision acme auth r >/dev/null 2>&1"
seq_dir; inv 1 "$OK"
check "a send failure is reported"                      bash -c "! FAKE_SEND_FAIL=1 run >/dev/null 2>&1"
check "a bad service name is refused"                   bash -c "! bash '$P' core-database-provision acme 'Bad Name' eu-west-1 >/dev/null 2>&1"
check "a document name with a space is refused"         bash -c "! bash '$P' 'AWS RunShellScript' acme auth eu-west-1 >/dev/null 2>&1"
check "missing arguments are refused"                   bash -c "! bash '$P' core-database-provision >/dev/null 2>&1"
finish
