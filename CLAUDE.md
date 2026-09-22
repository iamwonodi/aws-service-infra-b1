# Working on this repository

This is a **blueprint**: many services clone it. Never commit anything service- or project-specific; per-service values ship as `CHANGE_ME`.

## Ground rules

- **Never run `terraform plan` or `terraform apply`**, or any AWS-mutating command, unless asked in that specific request. `terraform fmt` and `terraform validate` are fine.
- Read the real files, and the modules a file calls, before proposing a change. Verify against provider documentation rather than recalling.
- Ask before building. Classify review findings CRITICAL / HIGH / MEDIUM / LOW / OPTIONAL, say PASS when something is correct, and do not rewrite working code for style.
- Comments explain why, not what. Scripts are exercised against real inputs and their error paths before they are called done.

## Where things live

`modules/service-model` is pure (no resources) and tested with `terraform test`; put every check and derivation there. `modules/service` creates resources and composes the platform's own modules. `modules/service-hosting` is the service's own hosts, used only where the platform hosts services dedicated. The environment folders only pass variables through.

## Contracts with the other repositories

- **Core** publishes `/<project>/platform/config` (schema version 1) and generates this repository's IAM role from a `service-roles.json` entry of `kind: infra`. The role can touch only resources named `<project>-<service>-<environment>*`, keys under `services/<service>/` in the state bucket, and resources whose `Service` tag equals the service's name.
- **The application repository** reads `/<project>/services/<service>/config` ([docs/service-config.md](docs/service-config.md)). Changing its shape means bumping `schema_version`.

## Checks before a commit

```bash
terraform fmt -recursive
(cd modules/service-model && terraform init -backend=false && terraform test)
(cd infrastructure/development && terraform init -backend=false && terraform validate)
bash scripts/ci/tests/run-all.sh
```

## Open items

- Dedicated hosting (staging, production) is built in `modules/service-hosting` but has never run. Watch the first apply for: the boundary refusing an action the hosts need, the launch template module's `block_device_mappings` shape, and the boot script's `jq` being present on the image.
- Provisioning works against the EC2 database host only (`provision-database.sh`, after the apply). A managed database has no container to run core's provisioning script in; a service that declares a database in such an environment fails the plan.
- Nothing here has been planned or applied against real AWS. `modules/service` composes modules whose behaviour offline tests cannot prove.
- `.terraform.lock.hcl` is not committed yet (it needs registry access to generate).
- Every `infrastructure/<env>/.terraform.lock.hcl` is committed, locked for every platform (`terraform providers lock -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_amd64 -platform=darwin_arm64`). CI fails without it, and every environment init is `-lockfile=readonly`: after adding a provider or a module that brings one, re-lock and commit before pushing.
- Names: `<project>-<environment>-<service>-<resource>`. The secret and the target group are the one exception (`<project>-<service>-<environment>-...`, from `secrets-vault` and `target-group` v1), kept behind `service_first_name` in `service-model` and `secret_prefix` in `service-hosting`. Hosting models are `shared` and `dedicated`. Say **port registry** or **ECR registry**, never "the registry".

