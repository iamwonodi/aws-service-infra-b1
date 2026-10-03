#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
C="${SCRIPTS}/ci/check-lock-files.sh"

echo "== check-lock-files.sh"
R="${WORK}/lockrepo"; rm -rf "$R"; mkdir -p "$R/env"; cd "$R" && git init -q . && git config user.email t@t && git config user.name t
cat > env/versions.tf <<'TF'
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws" }
    random = { source = "hashicorp/random" }
  }
}
TF
lock(){ printf '%s\n' "$@" > env/.terraform.lock.hcl; }
# prov <name> <h1 count>: a provider block as terraform writes it, with that many h1: hashes.
prov(){ printf 'provider "registry.terraform.io/hashicorp/%s" {\n  version = "1.0.0"\n  hashes = [\n' "$1"
        for ((i=0;i<$2;i++)); do printf '    "h1:%s%s=",\n' "$1" "$i"; done
        printf '    "zh:abc",\n  ]\n}\n\n'; }

check "no lock file fails"                   bash -c "! bash '$C' env >/dev/null 2>&1"
{ prov aws 4; prov random 4; } > env/.terraform.lock.hcl
check "an untracked lock file fails"         bash -c "! bash '$C' env >/dev/null 2>&1"
git add env/.terraform.lock.hcl
check "a tracked, complete lock file passes" bash "$C" env
prov aws 4 > env/.terraform.lock.hcl; git add env/.terraform.lock.hcl
out="$(bash "$C" env 2>&1)"; rc=$?
check "a lock file missing a declared provider fails" test $rc -ne 0
check "and names the missing provider"       bash -c "grep -q 'hashicorp/random' <<< \"$out\""
{ prov aws 1; prov random 1; } > env/.terraform.lock.hcl; git add env/.terraform.lock.hcl
out="$(bash "$C" env 2>&1)"; rc=$?
check "one h1 per provider (a plain terraform init) fails" test $rc -ne 0
check "and names both providers with their count" bash -c "grep -q 'hashicorp/aws has 1' <<< \"$out\" && grep -q 'hashicorp/random has 1' <<< \"$out\""
check "and prints the lock command"          bash -c "grep -q 'terraform providers lock -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_amd64 -platform=darwin_arm64' <<< \"$out\""
{ prov aws 4; prov random 1; } > env/.terraform.lock.hcl; git add env/.terraform.lock.hcl
out="$(bash "$C" env 2>&1)"; rc=$?
check "one good and one thin provider fails" test $rc -ne 0
check "naming only the thin one"             bash -c "grep -q 'hashicorp/random has 1' <<< \"$out\" && ! grep -q 'hashicorp/aws has' <<< \"$out\""
{ prov aws 3; prov random 4; } > env/.terraform.lock.hcl; git add env/.terraform.lock.hcl
check "three h1 is not enough"               bash -c "! bash '$C' env >/dev/null 2>&1"
mkdir -p env2; cp env/versions.tf env2/
check "every directory is checked, not just the first" bash -c "! bash '$C' env env2 >/dev/null 2>&1"
check "no directory given fails"             bash -c "! bash '$C' >/dev/null 2>&1"
cd - >/dev/null
finish
