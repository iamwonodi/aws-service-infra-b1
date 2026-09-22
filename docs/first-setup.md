# First setup

Run this once per service, in a clone of this blueprint. Everything is per **environment**, and only `development` is enabled today.

## 0. Prerequisites

| Tool | Why |
| --- | --- |
| `terraform` at the version in `.terraform-version` | everything, including CI, uses that one file |
| `gh`, authenticated (`gh auth login`) | GitHub Environments and secrets |
| `jq`, `git`, `bash` (Git Bash on Windows) | the scripts |

The platform (core) must already be running in the environment, so that `/<project>/platform/config` exists, and you need read access to core's repository.

## 1. Set the service's values

```bash
scripts/init-service.sh --project acme --service auth --region eu-west-1 --port 1024
```

Options: `--type web`, `--tier private|internal`, `--database postgres|mysql|none`, `--reviewers`. Preview with `--dry-run`. It writes `terraform.tfvars` and `backend.tf`, and creates the `development` and `development-plan` GitHub Environments here.

- `--service` must match the name core knows the service by (the `service_name` in core's `service-roles.json`), and `--project` the project core was set up with.
- `--port` is the host port. Services share a host, so it must be unique on the tier.
- The state key is `services/<service>/terraform.tfstate`. Core lets this repository's role touch only keys under `services/<service>/`.

Then run `terraform init` in `infrastructure/development` and commit the `.terraform.lock.hcl` it creates.

## 2. Ask core for a role

```bash
scripts/print-role-entry.sh
```

prints this repository's entry, with its numeric IDs. Paste it into core's `infrastructure/<env>/data/service-roles.json` for each environment, next to the application repository's own entry (each repository prints its own), and open a pull request in core. Both entries must use the same `service_name` and `tier`.

## 3. Connect to the role

After core has applied it:

```bash
scripts/fetch-role-arn.sh --core OWNER/CORE-REPOSITORY --environment development
```

reads this repository's role ARN from core's `platform-outputs` branch and sets `TF_AWS_ROLE_ARN` on both `development` and `development-plan`.

## 4. Optional: the port registry

To enforce that no two services on a tier share a host port, create a small repository to hold the registry, then set on **this** repository:

- variable `PORT_REGISTRY_REPOSITORY`: `OWNER/REPO` of the port registry
- secret `PORT_REGISTRY_TOKEN`: a token that can push to the port registry

The pull request check only reads; the claim happens after a successful apply, so an abandoned pull request never holds a port. Without these the check is skipped, with a warning in every plan.

## 5. The service's database

Set `database_engine` in `terraform.tfvars` (`postgres`, `mysql`, or leave it null). Terraform then generates the credentials into the service's secret and publishes a provisioning request; the apply workflow sends core's provisioning document to the database host, which creates the database, the user and its grants and waits for the result.

For anything beyond that -- an extension, a schema -- set `database_extra_sql_path` to a file of SQL. It runs as the **service's own user** on the service's own database, so it cannot reach another service's data, and it must be safe to run again: provisioning runs on every apply.

The database's **port** is not set here: the platform team publishes each engine's port, and the application repository reads it at deploy time.

## 6. Pull requests from here on

Open a pull request. `terraform-plan.yml` comments the plan. Merge, and `terraform-apply.yml` applies exactly that plan.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| A plan stops with `CHANGE_ME` | Run `scripts/init-service.sh` |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Core has not applied this repository's entry, its IDs are wrong, or `TF_AWS_ROLE_ARN` is missing on the `-plan` environment |
| A `Service` tag or `AccessDenied` on a rule or tag | Core's policy lets this role change only resources whose `Service` tag is this service's name |
| `the platform publishes no provisioning document` | The environment has no database host to provision on (a managed database), which this version does not support |
| `The platform offers no tier ...` | The tier is wrong, or core has not published the contract in this environment |
| `... publishes no golden image parameter` | Core has not built this environment's image yet, or predates it |
| `... must carry the platform's permissions boundary` | Core has not created the boundary in this environment |
