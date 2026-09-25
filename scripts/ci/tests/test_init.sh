#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
INIT="${SCRIPTS}/init-service.sh"
SOURCE_ROOT="$(cd "${SCRIPTS}/.." && pwd)"

fresh(){
  rm -rf "${WORK}/repo"; mkdir -p "${WORK}/repo/scripts/ci" "${WORK}/repo/.github"
  cp -r "${SOURCE_ROOT}/infrastructure" "${WORK}/repo/infrastructure"
  find "${WORK}/repo" -name '.terraform*' -prune -exec rm -rf {} + 2>/dev/null
  # Each case pins which environments are enabled, rather than inheriting the
  # repository's own list.
  echo '["development"]' > "${WORK}/repo/.github/environments.json"
  cp "${SCRIPTS}/ci/check-placeholders.sh" "${SCRIPTS}/ci/enabled-environments.sh" "${WORK}/repo/scripts/ci/"
  git -C "${WORK}/repo" init -q; git -C "${WORK}/repo" remote add origin https://github.com/acme/auth-infra.git
  export INIT_REPO_ROOT="${WORK}/repo" FAKE_GH_LOG="${WORK}/gh.log"; : > "${FAKE_GH_LOG}"
}
ARGS=(--project acme --service auth --region eu-west-1 --port 1234 --reviewers alice)
run(){ bash "${INIT}" "${ARGS[@]}" "$@"; }
val(){ sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "${WORK}/repo/infrastructure/$1/$3" | head -1; }
raw(){ sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\([^ #]*\).*/\1/p" "${WORK}/repo/infrastructure/$1/$3" | head -1; }

echo "== files"
fresh; run >"${WORK}/out.txt" 2>&1; rc=$?
check "run succeeds"                                     test $rc -eq 0
check "project, region, service written"                 bash -c "[ \"$(val development project_name terraform.tfvars)\" = acme ] && [ \"$(val development aws_region terraform.tfvars)\" = eu-west-1 ] && [ \"$(val development service_name terraform.tfvars)\" = auth ]"
check "port written as a number"                         test "$(raw development service_port terraform.tfvars)" = 1234
check "no CHANGE_ME remains outside comments"            bash -c "! grep -v '^[[:space:]]*#' '${WORK}/repo/infrastructure/development/terraform.tfvars' | grep -q CHANGE_ME"
check "database engine written"                          test "$(val development database_engine terraform.tfvars)" = postgres
check "state bucket named per environment"               test "$(val development bucket backend.tf)" = acme-development-tfstate
check "state key is under services/<service>/"           test "$(val development key backend.tf)" = services/auth/terraform.tfstate
check "backend region written"                           test "$(val development region backend.tf)" = eu-west-1
check "tier and type keep their values"                  bash -c "[ \"$(val development tier terraform.tfvars)\" = private ] && [ \"$(val development service_type terraform.tfvars)\" = web ]"
check "comments in backend.tf survive"                   grep -q 'native S3 locking' "${WORK}/repo/infrastructure/development/backend.tf"
check "no placeholder remains"                           bash "${WORK}/repo/scripts/ci/check-placeholders.sh" "${WORK}/repo/infrastructure/development"
snap="$(cat "${WORK}/repo"/infrastructure/development/{terraform.tfvars,backend.tf} | sha256sum)"
run >/dev/null 2>&1
check "re-running changes nothing (idempotent)"          test "$(cat "${WORK}/repo"/infrastructure/development/{terraform.tfvars,backend.tf} | sha256sum)" = "$snap"
fresh; run --tier internal --database none --type api >/dev/null 2>&1
check "--tier, --type honoured"                          bash -c "[ \"$(val development tier terraform.tfvars)\" = internal ] && [ \"$(val development service_type terraform.tfvars)\" = api ]"
check "--database none writes null"                      test "$(raw development database_engine terraform.tfvars)" = null
run --database mysql >/dev/null 2>&1
check "switching back to an engine replaces null"        test "$(val development database_engine terraform.tfvars)" = mysql
run --database mongodb >/dev/null 2>&1
check "mongodb is accepted (development runs it on the host)" test "$(val development database_engine terraform.tfvars)" = mongodb
fresh; run --project other >/dev/null 2>&1
check "re-running with a new project updates the files"  test "$(val development project_name terraform.tfvars)" = other

echo "== GitHub environments (only enabled ones)"
fresh; run >/dev/null 2>&1
for e in development development-plan; do
  check "environment $e configured"                      grep -q "^gh api -X PUT repos/acme/auth-infra/environments/$e --input -" "${FAKE_GH_LOG}"
  check "AWS_REGION set on $e"                           grep -q "^gh variable set AWS_REGION --repo acme/auth-infra --env $e --body eu-west-1" "${FAKE_GH_LOG}"
done
check "a disabled environment is NOT touched"             bash -c "! grep -q 'environments/staging' '${FAKE_GH_LOG}'"
body_of(){ grep -A1 "environments/$1 --input" "${FAKE_GH_LOG}" | grep '^BODY' | head -1 | sed 's/^BODY //'; }
check "development has no reviewers"                     bash -c "echo '$(body_of development)' | jq -e '.reviewers == []' >/dev/null"
check "the apply environment is limited to main"         bash -c "echo '$(body_of development)' | jq -e '.deployment_branch_policy.custom_branch_policies == true' >/dev/null"
check "the plan environment is NOT limited to a branch"  bash -c "echo '$(body_of development-plan)' | jq -e '.deployment_branch_policy == null' >/dev/null"
check "main is the allowed branch"                       grep -q 'BODY {"name":"main","type":"branch"}' "${FAKE_GH_LOG}"
# a later step adds staging: reviewers are then required there
fresh; echo '["development","staging"]' > "${WORK}/repo/.github/environments.json"
run >/dev/null 2>&1
check "an enabled staging requires the reviewers"        bash -c "echo '$(body_of staging)' | jq -e '(.reviewers | length) == 1 and .reviewers[0].id == 4242' >/dev/null"
check "and its plan environment too"                     bash -c "echo '$(body_of staging-plan)' | jq -e '(.reviewers | length) == 1' >/dev/null"
check "staging files are written as well"                test "$(val staging bucket backend.tf)" = acme-staging-tfstate
fresh; bash "${INIT}" --project acme --service auth --region eu-west-1 --port 1234 --skip-github >/dev/null 2>&1
check "--skip-github makes no gh call"                   test ! -s "${FAKE_GH_LOG}"

echo "== dry run"
fresh; before="$(cat "${WORK}/repo"/infrastructure/development/* | sha256sum)"; out="$(run --dry-run 2>&1)"
check "dry run changes no file"                          test "$(cat "${WORK}/repo"/infrastructure/development/* | sha256sum)" = "$before"
check "dry run makes no gh call"                         test ! -s "${FAKE_GH_LOG}"
check "dry run describes the work"                       bash -c "grep -q 'services/auth' <<< \"$out\" && grep -q 'dry run' <<< \"$out\""

echo "== validation (nothing is written on error)"
bad(){ fresh; before="$(cat "${WORK}/repo"/infrastructure/development/* | sha256sum)"; bash "${INIT}" "$@" >/dev/null 2>&1; rc=$?
       [[ $rc -ne 0 && "$(cat "${WORK}/repo"/infrastructure/development/* | sha256sum)" = "$before" && ! -s "${FAKE_GH_LOG}" ]]; }
check "bad project"                                      bad --project Bad --service auth --region eu-west-1 --port 1234
check "bad service"                                      bad --project acme --service Auth_1 --region eu-west-1 --port 1234
check "a platform-reserved service name"                 bad --project acme --service database-hub --region eu-west-1 --port 1234
check "bad region"                                       bad --project acme --service auth --region nowhere --port 1234
check "privileged port"                                  bad --project acme --service auth --region eu-west-1 --port 80
check "missing port"                                     bad --project acme --service auth --region eu-west-1
check "bad tier"                                         bad --project acme --service auth --region eu-west-1 --port 1234 --tier edge
check "bad database"                                     bad --project acme --service auth --region eu-west-1 --port 1234 --database redis
check "a name matching an administrator secret"          bad --project acme --service database-admin-postgres --region eu-west-1 --port 1234
check "bad reviewers"                                    bad --project acme --service auth --region eu-west-1 --port 1234 --reviewers 'a b'
check "unknown option"                                   bad --project acme --service auth --region eu-west-1 --port 1234 --bogus
fresh; FAKE_GH_NO_USER=1 bash "${INIT}" "${ARGS[@]}" >/dev/null 2>&1
check "an unknown reviewer login fails"                  test $? -ne 0
echo "== the repository as shipped"
fresh; cp "${SOURCE_ROOT}/.github/environments.json" "${WORK}/repo/.github/"
run >/dev/null 2>&1; rc=$?
check "all three shipped environments initialise"        test $rc -eq 0
check "production files are written too"                 test "$(val production bucket backend.tf)" = acme-production-tfstate
check "and production is guarded by the reviewers"       bash -c "echo '$(body_of production)' | jq -e '(.reviewers | length) == 1' >/dev/null"
echo "== environments"
fresh; run --environments production,development >"${WORK}/out.txt" 2>&1; rc=$?
check "--environments succeeds"                        test $rc -eq 0
check "the list is written, in order"                  bash -c "[ \"\$(jq -c . '${WORK}/repo/.github/environments.json')\" = '[\"development\",\"production\"]' ]"
check "production's files are set"                    bash -c "grep -qx 'service_name *= *\"auth\"' '${WORK}/repo/infrastructure/production/terraform.tfvars' || grep -q 'service_name = \"auth\"' '${WORK}/repo/infrastructure/production/terraform.tfvars'"
check "staging's are left alone"                       grep -q CHANGE_ME "${WORK}/repo/infrastructure/staging/terraform.tfvars"
check "no GitHub Environment for staging"              bash -c "! grep -q 'environments/staging' '${FAKE_GH_LOG}'"
fresh; echo '["development","prod"]' > "${WORK}/repo/.github/environments.json"
check "a misspelt list is refused"                     bash -c "! bash '${INIT}' ${ARGS[*]} >/dev/null 2>&1"
fresh
check "an unknown --environments is refused"           bash -c "! bash '${INIT}' ${ARGS[*]} --environments prod >/dev/null 2>&1"
finish
