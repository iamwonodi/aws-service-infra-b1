# ------------------------------------------------------------------------------
# SERVICE MODEL
#
# Everything that can be worked out about a service BEFORE any resource exists:
# what the platform offers, which tier resources the service attaches to, its
# names, and the document its application repository reads to deploy it. It
# creates no resources, so it is tested without AWS.
#
# Two hosting models, decided by the platform, not by this repository:
#
#   shared         development. Services share the tier's fleet; this service
#                  attaches its target group to it and publishes into the shared
#                  deploy bucket.
#   dedicated      staging, production. This service creates its OWN hosts, its
#                  own security group, its own configuration bucket and its own
#                  update document. Core still owns the image those hosts boot
#                  and the scripts they run.
#
# The invariants below stop the plan with a message naming the cause, instead of
# letting a wrong tier, a dedicated environment this blueprint does not yet host,
# or a name AWS would truncate reach the API.
# ------------------------------------------------------------------------------

locals {
  platform = jsondecode(var.platform_json)

  hosting_model = try(local.platform.hosting_model, null)
  is_dedicated  = local.hosting_model == "dedicated"
  tier          = try(local.platform.tiers[var.tier], null)

  domain = "${coalesce(var.subdomain, var.service_name)}.${try(local.platform.domain_name, "unknown")}"

  # <project>-<service>-<environment>: the order terraform-aws-target-group v1 gives
  # the target group (and terraform-aws-secrets-vault v1 the secret). It is the ONE
  # exception to <project>-<environment>-<service>, which everything else here
  # follows, and goes when both modules release a v2.
  service_first_name = "${var.project_name}-${var.service_name}-${var.environment}"
  target_group_name  = "${local.service_first_name}-tg"

  # The one parameter through which the application repository learns about this
  # service. Written by this repository's role, read by the app repository's.
  parameter_name = "/${var.project_name}/services/${var.service_name}/config"

  # Where a dedicated service publishes what its own hosts read, and the document
  # it sends to redeploy them. Core's policy scopes both to this service's name.
  config_bucket        = "${var.project_name}-${var.environment}-${var.service_name}-config"
  update_document_name = "${var.project_name}-${var.service_name}-update"

  # Core owns the image and the deploy scripts even where the hosts are the
  # service's own, so that a fix is one rebuild and one upload rather than one
  # per service repository.
  ami_parameter              = try(local.platform.compute.ami_parameter, null)
  scripts_manifest_parameter = try(local.platform.compute.scripts_manifest_parameter, null)
  platform_prefix            = try(local.platform.compute.platform_prefix, "_platform")
  shared_deploy_bucket       = try(local.platform.buckets.deploy, null)

  # WHERE THE DATABASE IS depends on the hosting model:
  #
  #   shared      development. One EC2 database host runs every engine; the
  #               platforms team publishes each engine's port as an SSM parameter,
  #               which the application reads at deploy time.
  #   dedicated   staging, production. Each ACTIVE engine is its own managed
  #               instance, listed in the contract's database.engines with its
  #               host, port and provisioning function. An engine the environment
  #               does not run is simply absent, and the plan says so.
  managed_databases = try(local.platform.database.engines, {})
  managed_database  = var.database_engine == null ? null : try(local.managed_databases[var.database_engine], null)

  database_host = var.database_engine == null ? null : (
    local.is_dedicated ? try(local.managed_database.host, null) : try(local.platform.database.host, null)
  )

  # The port itself where the contract publishes it (managed); otherwise the
  # parameter the platforms team publishes it under.
  database_port           = local.is_dedicated ? try(local.managed_database.port, null) : null
  database_port_parameter = var.database_engine == null || local.is_dedicated ? null : "/${var.project_name}/database/engines/${var.database_engine}/port"

  # Provisioning: on the EC2 host this repository publishes a request, then sends
  # core's document to the host, which creates the database and user from the
  # secret. A managed database has no container to run that in, so core runs a
  # Lambda inside the VPC per engine, and this repository invokes that engine's.
  provision_document = var.database_engine == null || local.is_dedicated ? null : try(local.platform.database.provision_document, null)
  provision_function = var.database_engine == null || !local.is_dedicated ? null : try(local.managed_database.provision_function, null)

  provisioning_prefix = "provisioning/${var.service_name}"

  # Identifiers are the service name with underscores, which every supported
  # engine accepts unquoted.
  database_identifier = replace(var.service_name, "-", "_")

  # The service's agents: logins <database identifier>.<name>, at most 32
  # characters (MySQL's limit, which core holds on every engine).
  agent_logins     = { for name, agent in var.agents : name => "${local.database_identifier}.${name}" }
  agents_too_long  = [for name, login in local.agent_logins : login if length(login) > 32]
  agent_name_limit = 32 - length(local.database_identifier) - 1

  # Where the service declares its agents' emails to the front door. Null where
  # the platform has none (production).
  front_door_declaration_key = try(local.platform.team_front_door.declaration_prefix, null) == null ? null : "${local.platform.team_front_door.declaration_prefix}${var.service_name}.json"

  config = {
    schema_version = 1

    service_name  = var.service_name
    service_type  = var.service_type
    environment   = var.environment
    tier          = var.tier
    hosting_model = local.hosting_model

    domain            = local.domain
    port              = var.service_port
    health_check_path = var.health_check_path

    secret = {
      arn  = var.secret_arn
      name = var.secret_name
    }

    ecr = {
      repository_url  = var.ecr_repository_url
      repository_name = var.ecr_repository_name
    }

    target_group_arn = var.target_group_arn

    # Where the application repository publishes its compose file and .env, and
    # which document redeploys. On a shared fleet both belong to the tier; with
    # dedicated hosts both belong to this service alone.
    deploy = local.is_dedicated ? {
      bucket          = local.config_bucket
      prefix          = "services/${var.service_name}"
      update_document = local.update_document_name
      } : {
      bucket          = local.shared_deploy_bucket
      prefix          = "${var.tier}/${var.service_name}"
      update_document = try(local.platform.fleet_update_document, null)
    }

    static = {
      bucket = try(local.platform.buckets.assets, null)
      prefix = "static/${var.service_name}"
    }

    database = var.database_engine == null ? null : {
      engine = var.database_engine
      host   = local.database_host

      # Exactly one is set: port on a managed database, port_parameter on the EC2
      # host (read from SSM at deploy time).
      port           = local.database_port
      port_parameter = local.database_port_parameter
      secret_fields = {
        name     = "db_name"
        user     = "db_user"
        password = "db_password"
      }
    }
  }

  config_json = jsonencode(local.config)

  # What core's provisioning script reads. It names WHERE the credentials are, and
  # never contains one: the database host reads the secret itself.
  provisioning_request = var.database_engine == null ? null : {
    service_name         = var.service_name
    database_engine      = var.database_engine
    database_secrets_arn = var.secret_arn

    secret_mappings = {
      db_key   = "db_name"
      user_key = "db_user"
      pass_key = "db_password"
    }
  }

  provisioning_request_json = local.provisioning_request == null ? null : jsonencode(local.provisioning_request)
}

resource "terraform_data" "model_invariants" {
  lifecycle {
    # Agents are logins on the service's database.
    precondition {
      condition     = length(var.agents) == 0 || var.database_engine != null
      error_message = "agents.json lists agents, but the service has no database: an agent is a login on the service's database."
    }

    precondition {
      condition     = length(local.agents_too_long) == 0
      error_message = "These logins are longer than 32 characters, MySQL's limit: ${join(", ", local.agents_too_long)}. With this service's name an agent's name can be at most ${local.agent_name_limit} characters."
    }

    precondition {
      condition     = try(local.platform.schema_version, null) == 1
      error_message = "This blueprint was written for platform contract version 1, but core publishes version ${try(local.platform.schema_version, "unknown")} at /${var.project_name}/platform/config."
    }

    precondition {
      condition     = contains(["shared", "dedicated"], coalesce(local.hosting_model, "unknown"))
      error_message = "The platform reports hosting_model \"${coalesce(local.hosting_model, "unknown")}\", which this blueprint does not know how to build for."
    }

    precondition {
      condition     = local.tier != null
      error_message = "The platform offers no tier \"${var.tier}\" in this environment. Available: ${join(", ", keys(try(local.platform.tiers, {})))}.${var.tier == "internal" ? " Core runs the internal tier only while internal_tier_enabled is on in that environment's terraform.tfvars." : ""}"
    }

    # A shared fleet needs the tier's own group and ASG to attach to. Dedicated
    # hosting needs the tier's subnets, and the tier's group for its own hosts to
    # wear: the databases and the Secrets Manager endpoint admit that group, not
    # the service's own.
    precondition {
      condition = local.tier != null && alltrue([
        for key in local.is_dedicated ? ["listener_arn", "alb_security_group_id", "security_group_id", "subnet_ids"] : ["listener_arn", "alb_security_group_id", "security_group_id", "asg_name"] :
        try(local.tier[key], null) != null
      ])
      error_message = "The platform's ${var.tier} tier is missing something this hosting model needs: ${local.is_dedicated ? "listener_arn, alb_security_group_id, security_group_id or subnet_ids. A core published before dedicated hosts wore the tier's security group lacks security_group_id: update and apply core first" : "listener_arn, alb_security_group_id, security_group_id or asg_name"}."
    }

    precondition {
      condition     = local.is_dedicated || (try(local.platform.buckets.deploy, null) != null && try(local.platform.fleet_update_document, null) != null)
      error_message = "The platform publishes no shared deploy bucket or fleet-update document, which the shared fleet needs."
    }

    # Dedicated hosts boot core's image and install core's scripts, so both must
    # be published before this service can build anything.
    precondition {
      condition     = !local.is_dedicated || (local.ami_parameter != null && local.scripts_manifest_parameter != null && local.shared_deploy_bucket != null)
      error_message = "This environment hosts services dedicated, but the platform publishes no golden image parameter, script manifest or deploy bucket for their hosts to use."
    }

    precondition {
      condition     = !local.is_dedicated || try(local.platform.service_boundary_arn, null) != null
      error_message = "This environment hosts services dedicated, so every IAM role this repository creates must carry the platform's permissions boundary -- and the platform publishes none."
    }

    precondition {
      condition     = length(local.target_group_name) <= 32
      error_message = "The target group name ${local.target_group_name} is ${length(local.target_group_name)} characters; AWS allows 32. Shorten project_name or service_name."
    }

    precondition {
      condition     = var.database_engine == null || local.is_dedicated || try(local.platform.database.host, null) != null
      error_message = "database_engine is ${coalesce(var.database_engine, "unset")}, but the platform publishes no database host."
    }

    # A managed environment runs only the engines core lists for it, each billed
    # while it runs. Failing here names the fix instead of deploying a service
    # that could never reach its database.
    precondition {
      condition     = var.database_engine == null || !local.is_dedicated || local.managed_database != null
      error_message = "database_engine is ${coalesce(var.database_engine, "unset")}, but ${var.environment} runs ${length(local.managed_databases) == 0 ? "no database engine" : "only: ${join(", ", sort(keys(local.managed_databases)))}"}. Add it to database_engines in core's infrastructure/${var.environment}/terraform.tfvars (scripts/init-project.sh --${var.environment}-engines), or use an engine this environment runs."
    }

    precondition {
      condition     = local.managed_database == null || (try(local.managed_database.host, null) != null && try(local.managed_database.port, null) != null)
      error_message = "The platform lists ${coalesce(var.database_engine, "unset")} for ${var.environment} without a host or port."
    }
  }
}
