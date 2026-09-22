#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="${SCRIPTS}/ci/resolve-environments.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

repo(){ # enabled-json
  rm -rf "${WORK}/r"; mkdir -p "${WORK}/r/.github" "${WORK}/r/infrastructure/development" "${WORK}/r/infrastructure/staging" "${WORK}/r/modules/service" "${WORK}/r/scripts"
  printf '%s' "$1" > "${WORK}/r/.github/environments.json"
  ( cd "${WORK}/r" && git init -q -b main && touch infrastructure/development/a infrastructure/staging/a modules/service/a scripts/a README.md && git add -A && git commit -q -m base )
}
change(){ ( cd "${WORK}/r" && echo x >> "$1" && git add -A && git commit -q -m change ); }
run(){ RESOLVE_ROOT="${WORK}/r" bash "$R" "$@" 2>/dev/null; }
sha(){ git -C "${WORK}/r" rev-parse "$1"; }

echo "== resolve-environments.sh"
repo '["development"]'
change infrastructure/development/a
check "a development change runs development"          test "$(run pull_request "$(sha HEAD~1)" "$(sha HEAD)")" = '["development"]'
change modules/service/a
check "a module change runs every enabled environment" test "$(run pull_request "$(sha HEAD~1)" "$(sha HEAD)")" = '["development"]'
change scripts/a
check "a scripts-only change runs nothing"             test "$(run pull_request "$(sha HEAD~1)" "$(sha HEAD)")" = '[]'
change README.md
check "a docs-only change runs nothing"                test "$(run pull_request "$(sha HEAD~1)" "$(sha HEAD)")" = '[]'
repo '["development","staging"]'
change infrastructure/staging/a
check "only the changed enabled environment runs"      test "$(run pull_request "$(sha HEAD~1)" "$(sha HEAD)")" = '["staging"]'
change modules/service/a
check "a module change runs all enabled, in order"     test "$(run pull_request "$(sha HEAD~1)" "$(sha HEAD)")" = '["development","staging"]'
repo '["development"]'
change infrastructure/staging/a
check "a change to a NOT enabled environment is ignored" test "$(run pull_request "$(sha HEAD~1)" "$(sha HEAD)")" = '[]'
check "dispatch: an enabled environment"               test "$(run workflow_dispatch development)" = '["development"]'
check "dispatch: a disabled environment is refused"    bash -c "! RESOLVE_ROOT='${WORK}/r' bash '$R' workflow_dispatch staging >/dev/null 2>&1"
check "dispatch: an empty request is refused"          bash -c "! RESOLVE_ROOT='${WORK}/r' bash '$R' workflow_dispatch '' >/dev/null 2>&1"
check "an unknown event is refused"                    bash -c "! RESOLVE_ROOT='${WORK}/r' bash '$R' push >/dev/null 2>&1"
repo '{"not":"an array"}'
check "a malformed environments file is refused"       bash -c "! RESOLVE_ROOT='${WORK}/r' bash '$R' workflow_dispatch development >/dev/null 2>&1"
finish
