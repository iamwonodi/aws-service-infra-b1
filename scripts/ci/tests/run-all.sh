#!/usr/bin/env bash
# Offline tests for the scripts in this repository (needs bash, git, jq; gh is faked).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
failed=0
for suite in test_placeholders.sh test_lock_files.sh test_metadata.sh test_resolve_environments.sh test_registry.sh test_provisioning.sh test_invoke_provisioning.sh test_service_info.sh test_init.sh test_roles.sh test_platform.sh; do
  echo "################ ${suite}"
  bash "./${suite}" || failed=1
done
[[ ${failed} -eq 0 ]] && echo "ALL TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
