#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
S="${SCRIPTS}/ci/check-placeholders.sh"
mkenv(){ rm -rf "${WORK}/env"; mkdir -p "${WORK}/env/infrastructure/development" "${WORK}/env/local-config"; cd "${WORK}/env/infrastructure/development" || exit 1; }

echo "== check-placeholders.sh"
mkenv; printf 'service_name = "auth"\nservice_port = 1024\n' > terraform.tfvars; printf 'terraform {}\n' > backend.tf
check "a configured service passes"               bash "$S" .
mkenv; printf 'service_name = "CHANGE_ME"\n' > terraform.tfvars
out="$(bash "$S" . 2>&1)"; rc=$?
check "marker in tfvars fails"                    test $rc -eq 1
check "report names the file and line"            bash -c "grep -q 'terraform.tfvars:1:' <<< \"$out\""
check "message points at init-service.sh"         bash -c "grep -q 'init-service.sh' <<< \"$out\""
mkenv; printf 'service_port = 0 # CHANGE_ME\n' > terraform.tfvars
check "a trailing marker on a value line fails"   bash -c "! bash '$S' . >/dev/null 2>&1"
mkenv; printf '# replace CHANGE_ME below\nservice_name = "auth"\n' > terraform.tfvars
check "marker in a comment line is ignored"       bash "$S" .
mkenv; printf 'bucket = "CHANGE_ME-development-tfstate"\n' > backend.tf
check "marker in backend.tf fails"                bash -c "! bash '$S' . >/dev/null 2>&1"
mkenv; printf 'AWS_REGION=CHANGE_ME\n' > ../../local-config/development.vars.env
check "marker in local-config fails"              bash -c "! bash '$S' . >/dev/null 2>&1"
check "missing directory is an error"             bash -c "! bash '$S' /nonexistent >/dev/null 2>&1"
finish
