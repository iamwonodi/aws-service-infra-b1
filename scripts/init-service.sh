#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# INITIALISE A CLONE OF THIS BLUEPRINT FOR ONE SERVICE
#
# Values that differ per service ship as the marker CHANGE_ME, and CI refuses to
# plan while any remain. This script sets them and prepares GitHub to guard each
# environment. Safe to re-run: it rewrites only the values it owns and PUTs
# GitHub Environments idempotently.
#
# For every ENABLED environment (.github/environments.json):
#
#   Files   infrastructure/<env>/terraform.tfvars   project_name, aws_region,
#                                                   service_name, service_type,
#                                                   tier, service_port, database_engine
#           infrastructure/<env>/backend.tf         state bucket, key and region
#
#   GitHub  Environment <env>        guards the apply. Deployments only from main.
#           Environment <env>-plan   guards plans on pull requests.
#           Reviewers (if given) are required on every environment except
#           development. Each gets the AWS_REGION variable. TF_AWS_ROLE_ARN is set
#           later by scripts/fetch-role-arn.sh, once core has created the role.
#
# The state key is services/<service>/terraform.tfstate. Core's policy lets this
# repository's role touch ONLY keys under services/<service>/.
#
# Usage:
#   scripts/init-service.sh --project NAME --service NAME --region REGION --port N \
#       [--type web] [--tier private|internal] [--database postgres|mysql|mongodb|none] \
#       [--reviewers login1,login2] [--repo OWNER/REPO] [--skip-github] [--dry-run]
#
#   --project   the project core was set up with (bucket names derive from it)
#   --service   the service's name; must match core's service-roles.json
#   --port      the host port; unique per tier (the port registry enforces it)
#   --dry-run   show what would change; write and call nothing
#
# Needs: bash, sed, jq; gh (authenticated) unless --skip-github or --dry-run.
# ==============================================================================

REPO_ROOT="${INIT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

PROJECT="" SERVICE="" REGION="" PORT="" TYPE="web" TIER="private" DATABASE="postgres" REVIEWERS="" REPO=""
SKIP_GITHUB=false
DRY_RUN=false

usage() { sed -n '/^# Usage:/,/^# Needs:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | head -n -1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)     PROJECT="${2:-}"; shift 2 ;;
    --service)     SERVICE="${2:-}"; shift 2 ;;
    --region)      REGION="${2:-}"; shift 2 ;;
    --port)        PORT="${2:-}"; shift 2 ;;
    --type)        TYPE="${2:-}"; shift 2 ;;
    --tier)        TIER="${2:-}"; shift 2 ;;
    --database)    DATABASE="${2:-}"; shift 2 ;;
    --reviewers)   REVIEWERS="${2:-}"; shift 2 ;;
    --repo)        REPO="${2:-}"; shift 2 ;;
    --skip-github) SKIP_GITHUB=true; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "ERROR: unknown argument '$1'." >&2; usage >&2; exit 1 ;;
  esac
done

# ------------------------------------------------------------------------------
# Validation -- everything is checked before anything is written or called.
# ------------------------------------------------------------------------------
errors=()

[[ "${PROJECT}" =~ ^[a-z][a-z0-9-]{1,14}[a-z0-9]$ ]] || errors+=("--project must be 3-16 lowercase letters, digits or hyphens, starting with a letter.")
[[ "${SERVICE}" =~ ^[a-z][a-z0-9-]{1,20}[a-z0-9]$ ]] || errors+=("--service must be 3-22 lowercase letters, digits or hyphens, starting with a letter.")
case "${SERVICE}" in
  database|database-hub|fleet|internal|platform|private|services)
    errors+=("--service '${SERVICE}' is a name the platform itself uses; choose another.") ;;
  database-admin*)
    errors+=("--service must not begin with database-admin: core's database administrator secrets are named that way.") ;;
esac
[[ "${REGION}" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ ]] || errors+=("--region must look like af-south-1.")
[[ "${PORT}" =~ ^[0-9]+$ && "${PORT}" -ge 1024 && "${PORT}" -le 65535 ]] || errors+=("--port must be a whole number from 1024 to 65535.")
[[ "${TYPE}" =~ ^[a-z][a-z0-9-]{0,15}$ ]] || errors+=("--type must be 1-16 lowercase letters, digits or hyphens.")
[[ "${TIER}" == "private" || "${TIER}" == "internal" ]] || errors+=("--tier must be private or internal.")
case "${DATABASE}" in
  postgres|mysql|mongodb|none) ;;
  *) errors+=("--database must be postgres, mysql, mongodb or none.") ;;
esac
if [[ -n "${REPO}" && ! "${REPO}" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]]; then errors+=("--repo must be OWNER/REPOSITORY."); fi
if [[ -n "${REVIEWERS}" && ! "${REVIEWERS}" =~ ^[A-Za-z0-9-]+(,[A-Za-z0-9-]+)*$ ]]; then errors+=("--reviewers must be comma-separated GitHub logins."); fi

if [[ ${#errors[@]} -gt 0 ]]; then
  printf 'ERROR: %s\n' "${errors[@]}" >&2
  exit 1
fi

for command in sed jq; do
  command -v "${command}" >/dev/null 2>&1 || { echo "ERROR: required command not found: ${command}" >&2; exit 1; }
done

ENABLED_FILE="${REPO_ROOT}/.github/environments.json"
[[ -f "${ENABLED_FILE}" ]] || { echo "ERROR: ${ENABLED_FILE} not found." >&2; exit 1; }
mapfile -t ENVIRONMENTS < <(jq -r '.[]' "${ENABLED_FILE}")
[[ ${#ENVIRONMENTS[@]} -gt 0 ]] || { echo "ERROR: no environments are enabled in ${ENABLED_FILE}." >&2; exit 1; }

if [[ "${SKIP_GITHUB}" != "true" && "${DRY_RUN}" != "true" ]]; then
  command -v gh >/dev/null 2>&1 || { echo "ERROR: gh is required (or pass --skip-github)." >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not authenticated. Run: gh auth login" >&2; exit 1; }
fi

if [[ -z "${REPO}" && "${SKIP_GITHUB}" != "true" ]]; then
  REMOTE_URL="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
  [[ -n "${REMOTE_URL}" ]] || { echo "ERROR: no origin remote; pass --repo OWNER/REPOSITORY." >&2; exit 1; }
  REPO="$(sed -E 's#^(https?://[^/]+/|git@[^:]+:|ssh://[^/]+/)##; s#\.git$##; s#/$##' <<< "${REMOTE_URL}")"
fi

# ------------------------------------------------------------------------------
# Files
# ------------------------------------------------------------------------------

# Each replaces the value on the line that sets KEY, keeping alignment and any
# trailing comment. They write through a temporary file (sed -i differs between
# GNU and BSD) and fail loudly if the line is missing.
replace_value() {
  local file="$1" key="$2" pattern="$3" replacement="$4" tmp

  grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${file}" || { echo "ERROR: ${file} has no '${key} =' line to set." >&2; exit 1; }

  # The delimiter is a control character because the pattern and the replacement
  # can contain "|", "/" and "#" (an alternation, a state key, a path).
  local d=$'\001'

  tmp="$(mktemp)"
  sed -E "s${d}^([[:space:]]*${key}[[:space:]]*=[[:space:]]*)${pattern}${d}\\1${replacement}${d}" "${file}" > "${tmp}"
  cat "${tmp}" > "${file}"
  rm -f "${tmp}"
}

set_string() { replace_value "$1" "$2" '"[^"]*"' "\"$3\""; }
# The rest of the line goes too: the placeholder's own "# CHANGE_ME" comment is
# what marks the value as unset.
set_number() { replace_value "$1" "$2" '[0-9]+.*' "$3"; }
set_null_or_string() {
  if [[ "$3" == "null" ]]; then replace_value "$1" "$2" '("[^"]*"|null)' "null"; else replace_value "$1" "$2" '("[^"]*"|null)' "\"$3\""; fi
}

update_files() {
  local env dir engine
  engine="${DATABASE}"; [[ "${engine}" == "none" ]] && engine="null"

  for env in "${ENVIRONMENTS[@]}"; do
    dir="${REPO_ROOT}/infrastructure/${env}"
    [[ -f "${dir}/terraform.tfvars" && -f "${dir}/backend.tf" ]] \
      || { echo "ERROR: ${dir} is missing terraform.tfvars or backend.tf." >&2; exit 1; }

    echo "  ${env}: service=${SERVICE} tier=${TIER} port=${PORT} database=${DATABASE} state=${PROJECT}-${env}-tfstate:services/${SERVICE}/"

    [[ "${DRY_RUN}" == "true" ]] && continue

    set_string "${dir}/terraform.tfvars" project_name "${PROJECT}"
    set_string "${dir}/terraform.tfvars" aws_region "${REGION}"
    set_string "${dir}/terraform.tfvars" service_name "${SERVICE}"
    set_string "${dir}/terraform.tfvars" service_type "${TYPE}"
    set_string "${dir}/terraform.tfvars" tier "${TIER}"
    set_number "${dir}/terraform.tfvars" service_port "${PORT}"
    set_null_or_string "${dir}/terraform.tfvars" database_engine "${engine}"

    set_string "${dir}/backend.tf" bucket "${PROJECT}-${env}-tfstate"
    set_string "${dir}/backend.tf" key "services/${SERVICE}/terraform.tfstate"
    set_string "${dir}/backend.tf" region "${REGION}"
  done
}

# ------------------------------------------------------------------------------
# GitHub Environments
# ------------------------------------------------------------------------------

gh_call() {
  # gh_call <description> <gh args...>   (stdin is passed through)
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "  [dry run] gh $2 ${*:3}"
    if [[ "$*" == *"--input -"* ]]; then cat > /dev/null; fi
    return 0
  fi
  gh "${@:2}"
}

reviewer_json() {
  local login id out="[]"
  IFS=',' read -ra logins <<< "${REVIEWERS}"
  for login in "${logins[@]}"; do
    if [[ "${DRY_RUN}" == "true" ]]; then
      id=0
    else
      id="$(gh api "users/${login}" --jq '.id')" || { echo "ERROR: could not find GitHub user '${login}'." >&2; exit 1; }
    fi
    out="$(jq -c --argjson id "${id}" '. + [{type: "User", id: $id}]' <<< "${out}")"
  done
  echo "${out}"
}

configure_environment() {
  local name="$1" restrict_to_main="$2" reviewers="$3" body

  body="$(jq -cn --argjson reviewers "${reviewers}" --argjson restrict "${restrict_to_main}" \
    '{reviewers: $reviewers}
     + (if $restrict then {deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}}
        else {deployment_branch_policy: null} end)')"

  echo "  environment ${name}: reviewers=$(jq 'length' <<< "${reviewers}") main-only=${restrict_to_main}"

  printf '%s' "${body}" | gh_call "environment ${name}" api -X PUT "repos/${REPO}/environments/${name}" --input -

  if [[ "${restrict_to_main}" == "true" ]]; then
    # 422 means the policy already exists, which is the state we want.
    printf '%s' '{"name":"main","type":"branch"}' \
      | gh_call "branch policy ${name}" api -X POST "repos/${REPO}/environments/${name}/deployment-branch-policies" --input - 2>/dev/null || true
  fi

  gh_call "AWS_REGION ${name}" variable set AWS_REGION --repo "${REPO}" --env "${name}" --body "${REGION}" >/dev/null
}

configure_github() {
  local env reviewers with_reviewers="[]"

  [[ -n "${REVIEWERS}" ]] && with_reviewers="$(reviewer_json)"

  for env in "${ENVIRONMENTS[@]}"; do
    reviewers="[]"
    if [[ "${env}" != "development" ]]; then
      reviewers="${with_reviewers}"
      [[ -z "${REVIEWERS}" ]] && echo "  WARNING: no --reviewers given, so ${env} will have no required reviewer."
    fi

    configure_environment "${env}" true "${reviewers}"
    configure_environment "${env}-plan" false "${reviewers}"
  done
}

# ------------------------------------------------------------------------------
echo "Service files"
update_files

if [[ "${SKIP_GITHUB}" == "true" ]]; then
  echo "GitHub Environments: skipped (--skip-github)."
else
  echo "GitHub Environments in ${REPO}"
  configure_github
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo
  echo "Dry run: nothing was written and GitHub was not called."
  exit 0
fi

echo
echo "Checking that no placeholder remains."
placeholder_dirs=()
for env in "${ENVIRONMENTS[@]}"; do placeholder_dirs+=("${REPO_ROOT}/infrastructure/${env}"); done
bash "${REPO_ROOT}/scripts/ci/check-placeholders.sh" "${placeholder_dirs[@]}"

cat <<NEXT

Done. Next:

  1. Give core this repository's role entry:
       scripts/print-role-entry.sh
     Paste the JSON into core's infrastructure/<env>/data/service-roles.json
     (with the entry the application repository prints for itself) and open a
     pull request there.

  2. Once core has applied it, connect this repository to its role:
       scripts/fetch-role-arn.sh --core OWNER/CORE-REPOSITORY --environment development

  3. Commit these changes and open a pull request. CI plans it.

See docs/first-setup.md for the full walkthrough.
NEXT
