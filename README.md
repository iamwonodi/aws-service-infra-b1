# Service infrastructure blueprint

The Terraform for **one service** on the platform that [core](https://github.com/iamwonodi/audit) runs: its image repository, secret, target group, load balancer rule, and the connection to the shared fleet. It is one half of a service. The other half is the **application repository** (for example the Django blueprint), which builds the image and deploys it.

```text
   this repository                        the application repository
   (infrastructure)                       (build and deploy)
        |                                          |
        | creates                                  | reads
        v                                          v
  ECR, secret, target group,          /<project>/services/<service>/config
  ALB rule, ingress rule,   ------->   (one SSM parameter this repository
  ASG attachment                        writes and the application reads)
        |
        | discovers the platform through
        v
  /<project>/platform/config           (published by core)
```

The two repositories have separate roles, and neither can do the other's job: this one can create resources but never pushes an image or deploys; the application can push and deploy but can never create or change a resource. Core generates both roles from a `service-roles.json` entry for each.

## What it creates

| Resource | Notes |
| --- | --- |
| ECR repository `<service>/<type>` | immutable tags, scan on push, keeps the last 14 images |
| Secret `<project>-<service>-<env>-secret-vault` (see the exception below) | generated application secrets, and the database name, user and password when there is a database |
| Target group `<project>-<service>-<env>-tg` (see the exception below) | health check on `/health` |
| ALB rule | `<service>.<domain>` to the target group, tagged `Service=<service>` |
| Security group rule | the tier's load balancer may reach the service's port |
| Auto scaling group attachment | the target group joins the tier's shared fleet |
| SSM parameter `/<project>/services/<service>/config` | what the application repository reads; see [docs/service-config.md](docs/service-config.md) |
| The service's database and user | published as a provisioning request; core's script on the database host creates them |

Every name follows core's `<project>-<environment>-<service>-<resource>` convention (for example the config bucket `<project>-<env>-<service>-config`), because the permissions core grants this repository's role are scoped to exactly those names.

**One exception, for now:** the secret and the target group are `<project>-<service>-<env>-…`, because `terraform-aws-secrets-vault` and `terraform-aws-target-group` v1 name them that way. Both follow the rule once they release a v2. Until then the order lives in one local each (`service_first_name` in `service-model`, `secret_prefix` in `service-hosting`).

## Two hosting models

The platform decides, per environment, and this repository builds whichever it says:

| | Development: `shared` | Staging, production: `dedicated` |
| --- | --- | --- |
| Hosts | the tier's shared fleet | **the service's own** auto scaling group |
| Target group attached | to the shared fleet's group | to the service's own group |
| Compose file and `.env` | the shared deploy bucket, `<tier>/<service>/` | the service's own config bucket, `services/<service>/` |
| Redeploy | core's fleet-update document | the service's own `<project>-<service>-update` document |
| Health check | `EC2` (one service's failure must not replace a shared host) | `ELB` (the load balancer's view is the one that matters) |
| Database provisioning | core's SSM document on the EC2 database host | core's Lambda inside the VPC, invoked after the apply |
| Instance role | core's | the service's own, under core's permissions boundary |

```text
   dedicated                         core
   ─────────                         ────
   launch template  <── AMI ID  ──── /<project>/platform/ami/ubuntu
         |
         v                           _platform/  (deploy scripts)
   auto scaling group  ──installs──> verified against core's manifest
   1 on-demand + spot
         |
         v
   target group <── ALB rule <── the tier's load balancer
```

**Core still owns the image and the deploy scripts** even where the hosts are the service's own. A fix to either is then one rebuild or one upload, rather than one change in every service repository. The hosts read the AMI ID from core's SSM parameter at plan time, so core rebuilding the image gives this service a new launch template version on its next plan.

**Where the hosts go comes from the platform contract** (`tiers.<tier>.subnet_ids`), so nothing about the network is hard-coded here.

**The instance role cannot be more powerful than the platform allows.** Core's policy lets this repository create a role only under `/services/<service>/`, carrying the platform's permissions boundary and a `Service` tag. A role created any other way is refused by IAM.

### Capacity

Set per environment in `terraform.tfvars`. The defaults:

| | Staging | Production |
| --- | --- | --- |
| `min_size` / `desired_capacity` / `max_size` | 1 / 1 / 2 | 2 / 2 / 4 |
| `on_demand_base_capacity` | 1 | 1 |
| everything above the base | spot | spot |

At least one host is always on demand: a spot interruption taking every host at once would otherwise take the service down.

## What it does not do yet

- **A service's own extra SQL on a managed database.** On the EC2 database host it runs as the service's own user; core's function on a managed database runs only its standard statements, so `database_extra_sql_path` is refused there rather than silently ignored. Apply it from a migration in the application instead.

## Getting started

```bash
scripts/init-service.sh --project acme --service auth --region eu-west-1 --port 1024
```

then follow [docs/first-setup.md](docs/first-setup.md).

## Layout

```text
modules/service/          the resources above
modules/service-hosting/  the service's own hosts, where the platform hosts services dedicated
modules/service-model/    everything decided before any resource exists, and the checks
infrastructure/development/   thin: backend, provider, variables, one module call
infrastructure/staging|production/   the service's own hosts (dedicated)
scripts/                  init-service, print-role-entry, fetch-role-arn; ci/ has the workflows' helpers, with tests
.github/environments.json which environments CI runs
.terraform-version        the Terraform version everything uses
docs/                     setup guide, the service config, decisions
```

## How changes reach AWS

1. **Pull request.** `terraform-plan.yml` plans the changed environment under its `<env>-plan` GitHub Environment and comments the plan.
2. **Merge to `main`.** `terraform-apply.yml` applies exactly that plan under `<env>`, then claims the service's port in the registry (if one is configured).

## Testing

| What | How |
| --- | --- |
| The service model and its invariants | `terraform test` in `modules/service-model` (needs no AWS) |
| The scripts | `bash scripts/ci/tests/run-all.sh` (bash, git, jq; `gh` is faked) |

The resource module itself (`modules/service`) needs real AWS to exercise. `terraform validate` in `infrastructure/development` checks it against the provider and modules; the first real plan checks the rest.
