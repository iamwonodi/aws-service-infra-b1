#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
P="${SCRIPTS}/ci/port-registry.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

reg="${WORK}/clone"

setup(){
  rm -rf "${WORK}/reg.git" "${WORK}"/clone*
  git init -q --bare -b main "${WORK}/reg.git"
  git clone -q "${WORK}/reg.git" "${reg}" 2>/dev/null
  ( cd "${reg}" && git checkout -q -b main && echo '# registry' > README.md && git add . && git commit -q -m init && git push -q -u origin main )
}
# registry <action> <environment> <tier|-> <service> <port> <repo> [registry-dir]
registry(){
  local action="$1" env="$2" tier="$3" svc="$4" port="$5" repo="$6" dir="${7:-$reg}"
  local args=(--registry-dir "$dir" --environment "$env" --service "$svc" --type web --port "$port" --repo "$repo")
  [[ "$tier" != "-" ]] && args+=(--tier "$tier")
  bash "$P" "$action" "${args[@]}" >/dev/null 2>&1
}
not(){ ! "$@"; }
seed(){ mkdir -p "$(dirname "${reg}/$1")"; printf '%s' "$2" > "${reg}/$1"; }
remote_file(){ git -C "${WORK}/reg.git" show "main:$1" 2>/dev/null; }
DEV=development/private-service-registry.json

echo "== check (read-only)"
setup
check "a first claim is valid"                            registry check development private auth 1024 acme/auth-infra
check "check writes nothing"                              test -z "$(git -C "${reg}" status --porcelain)"
seed $DEV '{"billing":{"port":1024,"service_type":"web","repository":"acme/billing-infra"}}'
check "a port already used on the tier is refused"        not registry check development private auth 1024 acme/auth-infra
check "the same port on the OTHER tier is fine"           registry check development internal auth 1024 acme/auth-infra
check "another port on the same tier is fine"             registry check development private auth 1025 acme/auth-infra
check "a name owned by another repository is refused"     not registry check development private billing 1030 acme/other
check "the owner may update its own claim"                registry check development private billing 1024 acme/billing-infra
check "the owner may change its own port"                 registry check development private billing 1040 acme/billing-infra

echo "== promotion gate"
seed $DEV '{"auth":{"port":1024,"service_type":"web","repository":"acme/auth-infra"}}'
check "staging: registered in development -> allowed"     registry check staging - auth 1024 acme/auth-infra
check "staging: unknown to development -> refused"        not registry check staging - newsvc 1024 acme/auth-infra
check "staging: someone else's claim -> refused"          not registry check staging - auth 1024 acme/imposter
seed staging/service-registry.json '{"auth":{"port":1024,"service_type":"web","repository":"acme/auth-infra"}}'
check "production: registered in staging -> allowed"      registry check production - auth 1024 acme/auth-infra
check "staging: an already-registered service skips the gate" registry check staging - auth 1024 acme/auth-infra
check "staging: a name owned by another repo is refused"  not registry check staging - auth 1024 acme/other
seed staging/service-registry.json '{"other":{"port":1024,"service_type":"web","repository":"acme/other-infra"}}'
seed $DEV '{"newone":{"port":1300,"service_type":"web","repository":"acme/new-infra"}}'
check "staging does not check ports"                      registry check staging - newone 1024 acme/new-infra

echo "== claim"
setup
registry claim development private auth 1024 acme/auth-infra
check "the claim is pushed"                               bash -c "git -C '${WORK}/reg.git' show 'main:$DEV' | jq -e '.auth.port == 1024 and .auth.repository == \"acme/auth-infra\" and .auth.service_type == \"web\"' >/dev/null"
before="$(git -C "${WORK}/reg.git" rev-parse main)"
registry claim development private auth 1024 acme/auth-infra
check "repeating the same claim adds no commit"           test "$(git -C "${WORK}/reg.git" rev-parse main)" = "$before"
check "a conflicting claim is refused"                    not registry claim development private other 1024 acme/other
check "and pushes nothing"                                test "$(git -C "${WORK}/reg.git" rev-parse main)" = "$before"
registry claim development private auth 1077 acme/auth-infra
check "the owner may move its own port"                   bash -c "git -C '${WORK}/reg.git' show 'main:$DEV' | jq -e '.auth.port == 1077' >/dev/null"

echo "== two services claiming at once"
setup
git clone -q "${WORK}/reg.git" "${WORK}/clone2" 2>/dev/null
registry claim development private svca 1100 acme/a "${reg}" &
registry claim development private svcb 1101 acme/b "${WORK}/clone2" &
wait
check "both distinct claims land (rebased, none lost)"    bash -c "git -C '${WORK}/reg.git' show 'main:$DEV' | jq -e 'has(\"svca\") and has(\"svcb\")' >/dev/null"

setup
git clone -q "${WORK}/reg.git" "${WORK}/clone2" 2>/dev/null
registry claim development private svca 1200 acme/a "${reg}" &
registry claim development private svcb 1200 acme/b "${WORK}/clone2" &
wait
check "the same port claimed twice: exactly one wins"     bash -c "[ \"\$(git -C '${WORK}/reg.git' show 'main:$DEV' | jq 'length')\" = 1 ]"

echo "== validation"
setup
check "bad service name"                                  not registry check development private Bad_Name 1024 a/b
check "privileged port"                                   not registry check development private okname 80 a/b
check "non-numeric port"                                  not registry check development private okname abc a/b
check "malformed repository"                              not registry check development private okname 1024 nonsense
check "development needs a tier"                          not registry check development - okname 1024 a/b
check "unknown environment"                               not registry check qa - okname 1024 a/b
check "missing registry directory"                        not registry check staging - okname 1024 a/b /nonexistent
check "an unknown action"                                 not bash "$P" frobnicate
seed $DEV '[1,2]'
check "a corrupt registry is refused"                     not registry check development private okname 1024 a/b
finish
