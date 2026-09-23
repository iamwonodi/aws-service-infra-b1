# Decision log

| Decision | Why |
| --- | --- |
| A service is two repositories, infrastructure and application | Different jobs, cadence and review. Each gets its own least-privilege role, and only this one holds resource-creating permissions |
| This blueprint is framework-agnostic; the application decides which secrets it needs (`generated_secret_names`) | The infrastructure for a container behind a load balancer is the same for Django, Node or Go |
| One SSM parameter is the only handoff to the application repository | Neither repository needs the other's permissions |
| The platform is discovered through `/<project>/platform/config`, never through core's Terraform state | State holds every secret core generated |
| Environments are folders, not repositories | The same code proven in each environment; repositories per environment drift |
| `infrastructure/<env>` is thin; the logic is in `modules/` | Environments can differ in what they compose (dedicated hosting later) without duplicating logic |
| Everything decidable before any resource exists lives in a pure module (`service-model`) | It is tested offline, and its invariants stop a plan with a message naming the cause |
| Only environments in `.github/environments.json` run | A change to shared code must not make CI plan an environment that cannot yet be planned |
| The port is claimed after the apply, checked (read-only) on the pull request | An abandoned pull request must not hold a port for ever |
| Port and name registry is optional, and its absence is a warning on every plan | A blueprint should work without a second repository, but not silently |
| Resource names follow `<project>-<environment>-<service>-<resource>` | Core's role for this repository is scoped to exactly those names, and the order matches 16 of the 18 published modules |
| **Exception:** the secret and the target group stay `<project>-<service>-<environment>` | `terraform-aws-secrets-vault` and `terraform-aws-target-group` v1 name them that way. They follow the rule once both release a v2; until then it is one local each |
| The hosting models are `shared` and `dedicated` | `shared-fleet` named a mechanism where `dedicated` named an exclusivity, so the pair did not read as a pair |
| The optional registry is the **port registry**, set with `PORT_REGISTRY_REPOSITORY` and `PORT_REGISTRY_TOKEN` | "Registry" alone also means the ECR registry that holds container images |
| The Service tag is set on everything and required on the ALB rule | Core lets this role change a rule only while it carries `Service=<service>`; a missing tag fails closed |
| Generated secrets use only letters, digits and `-_.` | Other characters are corrupted by the env files the values pass through |
| This repository generates the database credentials; core's script creates the database and user | The secret is this repository's to own, and the SQL is core's, so every service is provisioned the same way and none writes its own CREATE DATABASE |
| The provisioning request names where the credentials are and never contains one | It is an object in a bucket that several roles can read; the database host reads the secret itself |
| Provisioning is triggered after the apply, on every apply | Core's provisioning is conditional throughout, so repeating it is harmless, and a rotated secret heals itself. A failed provisioning fails the workflow, rather than leaving a service that deploys and cannot connect |
| A service's extra SQL runs as its own user on its own database | Run as the administrator, one line of it would have full control of every other service's data on the same engine |
| The service config holds identifiers, never values | It is readable by the application repository's role and by anyone reading SSM |
| No CloudFront secret header condition on the ALB rule | The ALBs are internal, reachable only through the CloudFront VPC origin |
| The platform decides the hosting model; this repository builds either | Development shares fleets, staging and production give each service its own hosts. The same repository serves both, so a service's infrastructure is proven in development before it runs dedicated |
| Core owns the image and the deploy scripts even for a service's own hosts | A fix to either is one rebuild or one upload, not one change per service repository |
| The hosts' subnets come from the platform contract | Nothing about the network is hard-coded in a service repository, so the platform can change it |
| A dedicated group owns its target group and checks health by ELB | It runs one service and this configuration creates both, so the load balancer's view is the right one. A shared fleet is the opposite on both counts |
| The boot-time script download is inlined, a dozen lines, rather than using core's helper | A service repository has no copy of core's helper, and downloading the helper before it could be verified would only move the question |
| A managed database is provisioned by invoking core's Lambda after the apply | It has no host to send a document to. The payload names only the service, so this repository cannot point it at another's credential |
| The invoke checks the response's FunctionError, not just the CLI's exit status | A Lambda that raises still returns HTTP 200, so the exit status alone would report a failed provisioning as success |
| `database_extra_sql_path` is refused where the database is managed | Core's function runs no service-supplied SQL; silently ignoring the file would be worse than refusing it |
| Dedicated hosts wear the tier's security group (from the contract's `tiers.<tier>.security_group_id`) beside their own | The databases and the Secrets Manager endpoint admit the tier's group, not each service's, so hosts wearing only their own could reach neither their database nor their secret. The tier group has no inbound rules, so wearing it opens nothing on the hosts. Chosen over core admitting the tiers' CIDR ranges, which would let in anything placed in those subnets |
| Every environment folder commits its provider lock file, and CI enforces it | `terraform init` writes the lock file locally and nothing complains that it is untracked, so it is easy to leave out. A test step fails when one is missing or does not lock a provider the folder declares, and plan, apply and destroy run `init -lockfile=readonly`, which also refuses a lock file missing a provider only a module declares |
