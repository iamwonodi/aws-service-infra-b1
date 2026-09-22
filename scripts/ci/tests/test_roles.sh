#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
E="${SCRIPTS}/print-role-entry.sh"
F="${SCRIPTS}/fetch-role-arn.sh"
SOURCE_ROOT="$(cd "${SCRIPTS}/.." && pwd)"

repo(){
  rm -rf "${WORK}/repo"; mkdir -p "${WORK}/repo/infrastructure/development"
  cp "${SOURCE_ROOT}/infrastructure/development/terraform.tfvars" "${WORK}/repo/infrastructure/development/"
  sed -i 's/CHANGE_ME"$/auth"/; s/^service_name = "auth"/service_name = "auth"/' "${WORK}/repo/infrastructure/development/terraform.tfvars"
  git -C "${WORK}/repo" init -q; git -C "${WORK}/repo" remote add origin https://github.com/acme/auth-infra.git
  export INIT_REPO_ROOT="${WORK}/repo" FAKE_GH_LOG="${WORK}/gh.log"; : > "${FAKE_GH_LOG}"
}
export FAKE_GH_REPO_JSON='{"id": 222, "full_name": "acme/auth-infra", "created_at": "2026-09-01T10:00:00Z", "owner": {"id": 111}}'

echo "== print-role-entry.sh"
repo
sed -i 's/^service_name .*/service_name = "auth"/' "${WORK}/repo/infrastructure/development/terraform.tfvars"
out="$(bash "$E" 2>/dev/null)"; rc=$?
check "prints an entry"                                  test $rc -eq 0
check "it is valid JSON keyed by the repository"         bash -c "echo '$out' | jq -e 'keys == [\"acme/auth-infra\"]' >/dev/null"
check "kind is infra"                                    bash -c "echo '$out' | jq -e '.[\"acme/auth-infra\"].kind == \"infra\"' >/dev/null"
check "service and tier come from tfvars"                bash -c "echo '$out' | jq -e '.[\"acme/auth-infra\"].service_name == \"auth\" and .[\"acme/auth-infra\"].tier == \"private\"' >/dev/null"
check "the IDs are strings, as core expects"             bash -c "echo '$out' | jq -e '.[\"acme/auth-infra\"].owner_id == \"111\" and .[\"acme/auth-infra\"].repository_id == \"222\"' >/dev/null"
sed -i 's/^service_name .*/service_name = "CHANGE_ME"/' "${WORK}/repo/infrastructure/development/terraform.tfvars"
check "refuses while the service is not configured"      bash -c "! bash '$E' >/dev/null 2>&1"
check "gh failure is reported"                           bash -c "! FAKE_GH_FAIL=1 bash '$E' >/dev/null 2>&1"
check "unknown option rejected"                          bash -c "! bash '$E' --bogus >/dev/null 2>&1"

echo "== fetch-role-arn.sh"
repo
printf '{"environment":"development","core_deploy_role_arn":"arn:aws:iam::123456789012:role/core-admin","service_role_arns":{"acme/auth-infra":"arn:aws:iam::123456789012:role/services/auth/infra","acme/auth-app":"arn:aws:iam::123456789012:role/services/auth/app"}}' > "${WORK}/arns.json"
export FAKE_GH_ROLE_ARNS_FILE="${WORK}/arns.json"
bash "$F" --core acme/core --environment development >/dev/null 2>&1; rc=$?
check "succeeds"                                         test $rc -eq 0
check "the secret is set on the apply environment"       grep -q 'gh secret set TF_AWS_ROLE_ARN --repo acme/auth-infra --env development --body arn:aws:iam::123456789012:role/services/auth/infra' "${FAKE_GH_LOG}"
check "and on the plan environment"                      grep -q 'gh secret set TF_AWS_ROLE_ARN --repo acme/auth-infra --env development-plan --body arn:aws:iam::123456789012:role/services/auth/infra' "${FAKE_GH_LOG}"
check "it reads the platform-outputs branch"             grep -q 'contents/role-arns/development.json?ref=platform-outputs' "${FAKE_GH_LOG}"
check "it never sets the OTHER repository's role"        bash -c "! grep -q 'services/auth/app' '${FAKE_GH_LOG}'"
: > "${FAKE_GH_LOG}"
bash "$F" --core acme/core --environment development --repo acme/unknown >/dev/null 2>&1
check "a repository with no role is refused"             test $? -ne 0
check "and sets nothing"                                 bash -c "! grep -q 'secret set' '${FAKE_GH_LOG}'"
printf '{"service_role_arns":{"acme/auth-infra":"not-an-arn"}}' > "${WORK}/bad.json"; export FAKE_GH_ROLE_ARNS_FILE="${WORK}/bad.json"
check "a malformed ARN is refused"                       bash -c "! bash '$F' --core acme/core --environment development >/dev/null 2>&1"
export FAKE_GH_ROLE_ARNS_FILE="${WORK}/missing.json"
check "a missing role-arns file is reported"             bash -c "! bash '$F' --core acme/core --environment development >/dev/null 2>&1"
export FAKE_GH_ROLE_ARNS_FILE="${WORK}/arns.json"
check "bad --core"                                       bash -c "! bash '$F' --core nonsense --environment development >/dev/null 2>&1"
check "bad --environment"                                bash -c "! bash '$F' --core acme/core --environment qa >/dev/null 2>&1"
check "unknown option"                                   bash -c "! bash '$F' --bogus >/dev/null 2>&1"
finish
