# Run with: terraform test   (from this module's directory; no AWS access needed)

variables {
  project_name = "core"
  environment  = "development"
  service_name = "auth"
  service_type = "web"
  tier         = "private"
  service_port = 1024

  database_engine = "postgres"

  platform_json = <<-JSON
    {
      "schema_version": 1,
      "project_name": "core",
      "environment": "development",
      "region": "af-south-1",
      "domain_name": "dev.example.org",
      "private_domain": "dev.example.org",
      "vpc_id": "vpc-0abc",
      "hosting_model": "shared",
      "compute": { "ami_parameter": "/core/platform/ami/ubuntu", "scripts_manifest_parameter": "/core/platform/scripts-manifest", "platform_prefix": "_platform" },
      "service_boundary_arn": null,
      "buckets": { "deploy": "core-development-deploy", "assets": "core-development-assets" },
      "fleet_update_document": "core-fleet-update",
      "database": { "host": "db.dev.example.org", "provision_document": "core-database-provision" },
      "tiers": {
        "private":  { "listener_arn": "arn:aws:elasticloadbalancing:af-south-1:123456789012:listener/app/core-private-alb-development/50dc/f2f7", "alb_security_group_id": "sg-0privalb", "security_group_id": "sg-0priv", "asg_name": "core-development-private-asg" },
        "internal": { "listener_arn": "arn:aws:elasticloadbalancing:af-south-1:123456789012:listener/app/core-internal-alb-development/60dc/a2f7", "alb_security_group_id": "sg-0intalb", "security_group_id": "sg-0int", "asg_name": "core-development-internal-asg" }
      }
    }
  JSON
}

run "the_service_is_placed_on_its_tier_and_domain" {
  command = plan

  assert {
    condition     = output.domain == "auth.dev.example.org"
    error_message = "the service is served on <service>.<environment domain>"
  }

  assert {
    condition     = output.tier.asg_name == "core-development-private-asg" && output.tier.alb_security_group_id == "sg-0privalb"
    error_message = "the service attaches to its own tier's resources"
  }

  assert {
    condition     = output.parameter_name == "/core/services/auth/config"
    error_message = "the service config lives at /<project>/services/<service>/config, which is where core's policies let the two repositories meet"
  }

  assert {
    condition     = output.target_group_name == "core-auth-development-tg"
    error_message = "the target group name follows core's <project>-<service>-<env>-tg convention, which its policy is scoped to"
  }
}

run "the_service_config_carries_what_the_app_repository_needs" {
  command = plan

  variables {
    secret_arn          = "arn:aws:secretsmanager:af-south-1:123456789012:secret:core-auth-development-secret-vault-AbC123"
    secret_name         = "core-auth-development-secret-vault"
    target_group_arn    = "arn:aws:elasticloadbalancing:af-south-1:123456789012:targetgroup/core-auth-development-tg/abc"
    ecr_repository_url  = "123456789012.dkr.ecr.af-south-1.amazonaws.com/auth/web"
    ecr_repository_name = "auth/web"
  }

  assert {
    condition     = jsondecode(output.config_json).schema_version == 1 && jsondecode(output.config_json).port == 1024
    error_message = "the config is versioned and carries the port"
  }

  assert {
    condition     = jsondecode(output.config_json).deploy.bucket == "core-development-deploy" && jsondecode(output.config_json).deploy.prefix == "private/auth" && jsondecode(output.config_json).deploy.update_document == "core-fleet-update"
    error_message = "the app repository publishes to <tier>/<service>/ in the shared deploy bucket and redeploys with the fleet-update document"
  }

  assert {
    condition     = jsondecode(output.config_json).static.bucket == "core-development-assets" && jsondecode(output.config_json).static.prefix == "static/auth"
    error_message = "static files go under static/<service>/ in the assets bucket"
  }

  assert {
    condition     = jsondecode(output.config_json).secret.arn == "arn:aws:secretsmanager:af-south-1:123456789012:secret:core-auth-development-secret-vault-AbC123" && jsondecode(output.config_json).ecr.repository_name == "auth/web"
    error_message = "the secret and image repository are published"
  }

  assert {
    condition     = jsondecode(output.config_json).database.host == "db.dev.example.org" && jsondecode(output.config_json).database.port_parameter == "/core/database/engines/postgres/port" && jsondecode(output.config_json).database.secret_fields.password == "db_password"
    error_message = "the database host, the SSM parameter holding the engine's port, and the secret's field names are published"
  }

  # The config names WHERE a secret lives and which fields it has; it never
  # contains a value. (secret_fields maps a role to a field NAME.)
  assert {
    condition     = !strcontains(output.config_json, "django_secret_key") && jsondecode(output.config_json).database.secret_fields.password == "db_password"
    error_message = "the service config holds identifiers only, never a secret value"
  }

  assert {
    condition     = length(output.config_json) < 4096
    error_message = "the config must fit an SSM standard parameter"
  }
}

run "the_provisioning_request_names_where_the_credentials_are_never_a_credential" {
  command = plan

  variables {
    secret_arn = "arn:aws:secretsmanager:af-south-1:123456789012:secret:core-auth-development-secret-vault-AbC123"
  }

  assert {
    condition     = output.provision_document == "core-database-provision"
    error_message = "the platform's provisioning document must be picked up from the contract"
  }

  assert {
    condition     = output.provisioning_prefix == "provisioning/auth"
    error_message = "the request is published under the service's own prefix, which is all core's policy lets this repository write"
  }

  assert {
    condition     = jsondecode(output.provisioning_request_json).service_name == "auth" && jsondecode(output.provisioning_request_json).database_engine == "postgres"
    error_message = "the request must name the service and its engine"
  }

  assert {
    condition     = jsondecode(output.provisioning_request_json).database_secrets_arn == "arn:aws:secretsmanager:af-south-1:123456789012:secret:core-auth-development-secret-vault-AbC123" && jsondecode(output.provisioning_request_json).secret_mappings.pass_key == "db_password"
    error_message = "the request names WHERE the credentials are, and which fields hold them"
  }

  # The host reads the secret itself; a credential must never be in the request,
  # which is an object in a bucket several roles can read.
  assert {
    condition     = length([for key in keys(jsondecode(output.provisioning_request_json)) : key if strcontains(key, "password")]) == 0
    error_message = "the provisioning request must contain no credential"
  }
}

run "no_database_means_a_null_database_section" {
  command = plan

  variables {
    database_engine = null
  }

  assert {
    condition     = jsondecode(output.config_json).database == null && output.database_port_parameter == null && output.provisioning_request_json == null && output.provision_document == null
    error_message = "a service without a database publishes no database section and no provisioning request"
  }
}

run "an_internal_service_uses_the_internal_tier" {
  command = plan

  variables {
    tier = "internal"
  }

  assert {
    condition     = output.tier.asg_name == "core-development-internal-asg" && jsondecode(output.config_json).deploy.prefix == "internal/auth"
    error_message = "an internal service attaches to the internal fleet and publishes under internal/"
  }
}

run "a_subdomain_overrides_the_default" {
  command = plan

  variables {
    subdomain = "login"
  }

  assert {
    condition     = output.domain == "login.dev.example.org"
    error_message = "the subdomain replaces the service name"
  }
}

# ------------------------------------------------------------------------------
# Invariants
# ------------------------------------------------------------------------------

run "a_dedicated_environment_builds_the_services_own_hosts" {
  command = plan

  variables {
    platform_json = <<-JSON
      {
        "schema_version": 1, "domain_name": "example.org", "hosting_model": "dedicated",
        "service_boundary_arn": "arn:aws:iam::123456789012:policy/platform/core-service-boundary",
        "compute": { "ami_parameter": "/core/platform/ami/ubuntu", "scripts_manifest_parameter": "/core/platform/scripts-manifest", "platform_prefix": "_platform" },
        "buckets": { "deploy": "core-production-deploy", "assets": "core-production-assets" },
        "database": {
          "host": "core-production-postgres.x.af-south-1.rds.amazonaws.com", "provision_function": "core-production-postgres-provision",
          "engines": {
            "postgres": { "host": "core-production-postgres.x.af-south-1.rds.amazonaws.com", "port": 5432, "provision_function": "core-production-postgres-provision" },
            "mysql":    { "host": "core-production-mysql.x.af-south-1.rds.amazonaws.com", "port": 3306, "provision_function": "core-production-mysql-provision" }
          }
        },
        "tiers": { "private": { "listener_arn": "arn:l", "alb_security_group_id": "sg-0alb", "subnet_ids": ["subnet-0a", "subnet-0b"] } }
      }
    JSON
  }

  assert {
    condition     = output.is_dedicated
    error_message = "the platform decides the hosting model, and it said dedicated"
  }

  # The service's own bucket and document, not the tier's.
  assert {
    condition     = jsondecode(output.config_json).deploy.bucket == "core-development-auth-config" && jsondecode(output.config_json).deploy.update_document == "core-auth-update"
    error_message = "a dedicated service publishes to its own bucket and redeploys with its own document"
  }

  assert {
    condition     = output.ami_parameter == "/core/platform/ami/ubuntu" && output.scripts_manifest_parameter == "/core/platform/scripts-manifest"
    error_message = "its hosts boot core's image and install core's scripts"
  }

  assert {
    condition     = output.provision_function == "core-production-postgres-provision" && output.provision_document == null
    error_message = "a managed database is provisioned by invoking core's function, not by sending a document"
  }

  # The engine's own instance and port, published directly: there is no port
  # parameter outside development.
  assert {
    condition     = jsondecode(output.config_json).database.host == "core-production-postgres.x.af-south-1.rds.amazonaws.com" && jsondecode(output.config_json).database.port == 5432 && jsondecode(output.config_json).database.port_parameter == null && output.database_port_parameter == null
    error_message = "on a managed database the app connects to its engine's instance on the published port"
  }

  assert {
    condition     = output.tier.subnet_ids == ["subnet-0a", "subnet-0b"]
    error_message = "the service learns where its hosts go from the contract, and hard-codes nothing"
  }

  assert {
    condition     = output.service_boundary_arn == "arn:aws:iam::123456789012:policy/platform/core-service-boundary"
    error_message = "every role this repository creates must carry the platform's boundary"
  }
}

run "a_dedicated_environment_without_an_image_is_refused" {
  command = plan

  variables {
    platform_json = "{\"schema_version\":1,\"domain_name\":\"x.org\",\"hosting_model\":\"dedicated\",\"service_boundary_arn\":\"arn:b\",\"buckets\":{\"deploy\":\"d\",\"assets\":\"a\"},\"tiers\":{\"private\":{\"listener_arn\":\"l\",\"alb_security_group_id\":\"s\",\"subnet_ids\":[\"a\",\"b\"]}}}"
  }

  expect_failures = [terraform_data.model_invariants]
}

run "a_dedicated_environment_without_a_boundary_is_refused" {
  command = plan

  variables {
    platform_json = "{\"schema_version\":1,\"domain_name\":\"x.org\",\"hosting_model\":\"dedicated\",\"compute\":{\"ami_parameter\":\"/a\",\"scripts_manifest_parameter\":\"/m\"},\"buckets\":{\"deploy\":\"d\",\"assets\":\"a\"},\"tiers\":{\"private\":{\"listener_arn\":\"l\",\"alb_security_group_id\":\"s\"}}}"
  }

  expect_failures = [terraform_data.model_invariants]
}

run "a_dedicated_tier_without_subnets_is_refused" {
  command = plan

  variables {
    platform_json = "{\"schema_version\":1,\"domain_name\":\"x.org\",\"hosting_model\":\"dedicated\",\"service_boundary_arn\":\"arn:b\",\"compute\":{\"ami_parameter\":\"/a\",\"scripts_manifest_parameter\":\"/m\"},\"buckets\":{\"deploy\":\"d\",\"assets\":\"a\"},\"tiers\":{\"private\":{\"listener_arn\":\"l\",\"alb_security_group_id\":\"s\"}}}"
  }

  expect_failures = [terraform_data.model_invariants]
}

run "an_unknown_hosting_model_is_refused" {
  command = plan

  variables {
    platform_json = "{\"schema_version\":1,\"domain_name\":\"x.org\",\"hosting_model\":\"serverless\",\"tiers\":{}}"
  }

  expect_failures = [terraform_data.model_invariants]
}

run "a_newer_contract_version_is_refused" {
  command = plan

  variables {
    platform_json = "{\"schema_version\":2,\"domain_name\":\"x.org\",\"hosting_model\":\"shared\",\"tiers\":{}}"
  }

  expect_failures = [terraform_data.model_invariants]
}

run "a_tier_the_platform_does_not_offer_is_refused" {
  command = plan

  variables {
    platform_json = "{\"schema_version\":1,\"domain_name\":\"x.org\",\"hosting_model\":\"shared\",\"buckets\":{\"deploy\":\"d\",\"assets\":\"a\"},\"fleet_update_document\":\"f\",\"tiers\":{\"internal\":{\"listener_arn\":\"l\",\"alb_security_group_id\":\"s\",\"security_group_id\":\"g\",\"asg_name\":\"a\"}}}"
  }

  expect_failures = [terraform_data.model_invariants]
}

run "a_tier_missing_the_shared_fleet_resources_is_refused" {
  command = plan

  variables {
    platform_json = "{\"schema_version\":1,\"domain_name\":\"x.org\",\"hosting_model\":\"shared\",\"buckets\":{\"deploy\":\"d\",\"assets\":\"a\"},\"fleet_update_document\":\"f\",\"tiers\":{\"private\":{\"listener_arn\":\"l\",\"alb_security_group_id\":\"s\"}}}"
  }

  expect_failures = [terraform_data.model_invariants]
}

run "a_database_engine_without_a_host_is_refused" {
  command = plan

  variables {
    platform_json = "{\"schema_version\":1,\"domain_name\":\"x.org\",\"hosting_model\":\"shared\",\"buckets\":{\"deploy\":\"d\",\"assets\":\"a\"},\"fleet_update_document\":\"f\",\"database\":{\"host\":null},\"tiers\":{\"private\":{\"listener_arn\":\"l\",\"alb_security_group_id\":\"s\",\"security_group_id\":\"g\",\"asg_name\":\"a\"}}}"
  }

  expect_failures = [terraform_data.model_invariants]
}

run "a_target_group_name_over_32_characters_is_refused" {
  command = plan

  variables {
    project_name = "averylongprojectn"
    service_name = "averylongservicenm"
  }

  expect_failures = [terraform_data.model_invariants]
}

run "a_platform_reserved_service_name_is_refused" {
  command = plan

  variables {
    service_name = "database-hub"
  }

  expect_failures = [var.service_name]
}

run "an_invalid_service_name_is_refused" {
  command = plan

  variables {
    service_name = "Auth_1"
  }

  expect_failures = [var.service_name]
}

run "a_privileged_port_is_refused" {
  command = plan

  variables {
    service_port = 80
  }

  expect_failures = [var.service_port]
}

run "an_unknown_tier_name_is_refused" {
  command = plan

  variables {
    tier = "edge"
  }

  expect_failures = [var.tier]
}

run "an_unsupported_database_engine_is_refused" {
  command = plan

  variables {
    database_engine = "redis"
  }

  expect_failures = [var.database_engine]
}

run "development_can_use_mongodb_on_the_database_host" {
  command = plan

  variables {
    database_engine = "mongodb"
  }

  assert {
    condition     = jsondecode(output.config_json).database.port_parameter == "/core/database/engines/mongodb/port" && jsondecode(output.config_json).database.port == null && output.provision_document == "core-database-provision"
    error_message = "on the EC2 host the port comes from the platforms team's parameter and provisioning is the host's document"
  }

  assert {
    condition     = jsondecode(output.provisioning_request_json).database_engine == "mongodb"
    error_message = "the host provisions the engine the service names"
  }
}

run "a_managed_service_uses_its_own_engines_instance" {
  command = plan

  variables {
    database_engine = "mysql"
    platform_json   = "{\"schema_version\":1,\"domain_name\":\"example.org\",\"hosting_model\":\"dedicated\",\"service_boundary_arn\":\"arn:b\",\"compute\":{\"ami_parameter\":\"/a\",\"scripts_manifest_parameter\":\"/m\"},\"buckets\":{\"deploy\":\"d\",\"assets\":\"a\"},\"tiers\":{\"private\":{\"listener_arn\":\"l\",\"alb_security_group_id\":\"s\",\"subnet_ids\":[\"a\",\"b\"]}},\"database\":{\"engines\":{\"postgres\":{\"host\":\"pg.rds\",\"port\":5432,\"provision_function\":\"core-production-postgres-provision\"},\"mysql\":{\"host\":\"my.rds\",\"port\":3306,\"provision_function\":\"core-production-mysql-provision\"}}}}"
  }

  assert {
    condition     = jsondecode(output.config_json).database.host == "my.rds" && jsondecode(output.config_json).database.port == 3306 && output.provision_function == "core-production-mysql-provision"
    error_message = "a mysql service connects to, and is provisioned by, the mysql instance -- not postgres"
  }
}

run "an_engine_the_managed_environment_does_not_run_is_refused" {
  command = plan

  variables {
    database_engine = "mysql"
    platform_json   = "{\"schema_version\":1,\"domain_name\":\"example.org\",\"hosting_model\":\"dedicated\",\"service_boundary_arn\":\"arn:b\",\"compute\":{\"ami_parameter\":\"/a\",\"scripts_manifest_parameter\":\"/m\"},\"buckets\":{\"deploy\":\"d\",\"assets\":\"a\"},\"tiers\":{\"private\":{\"listener_arn\":\"l\",\"alb_security_group_id\":\"s\",\"subnet_ids\":[\"a\",\"b\"]}},\"database\":{\"engines\":{\"postgres\":{\"host\":\"pg.rds\",\"port\":5432,\"provision_function\":\"f\"}}}}"
  }

  expect_failures = [terraform_data.model_invariants]
}

run "mongodb_is_refused_where_no_managed_mongodb_runs" {
  command = plan

  variables {
    database_engine = "mongodb"
    platform_json   = "{\"schema_version\":1,\"domain_name\":\"example.org\",\"hosting_model\":\"dedicated\",\"service_boundary_arn\":\"arn:b\",\"compute\":{\"ami_parameter\":\"/a\",\"scripts_manifest_parameter\":\"/m\"},\"buckets\":{\"deploy\":\"d\",\"assets\":\"a\"},\"tiers\":{\"private\":{\"listener_arn\":\"l\",\"alb_security_group_id\":\"s\",\"subnet_ids\":[\"a\",\"b\"]}},\"database\":{\"engines\":{\"postgres\":{\"host\":\"pg.rds\",\"port\":5432,\"provision_function\":\"f\"}}}}"
  }

  expect_failures = [terraform_data.model_invariants]
}

run "a_managed_environment_running_no_engine_is_refused" {
  command = plan

  variables {
    platform_json = "{\"schema_version\":1,\"domain_name\":\"example.org\",\"hosting_model\":\"dedicated\",\"service_boundary_arn\":\"arn:b\",\"compute\":{\"ami_parameter\":\"/a\",\"scripts_manifest_parameter\":\"/m\"},\"buckets\":{\"deploy\":\"d\",\"assets\":\"a\"},\"tiers\":{\"private\":{\"listener_arn\":\"l\",\"alb_security_group_id\":\"s\",\"subnet_ids\":[\"a\",\"b\"]}},\"database\":{\"host\":null,\"provision_function\":null,\"engines\":{}}}"
  }

  expect_failures = [terraform_data.model_invariants]
}

run "a_service_without_a_database_needs_no_engine" {
  command = plan

  variables {
    database_engine = null
    platform_json   = "{\"schema_version\":1,\"domain_name\":\"example.org\",\"hosting_model\":\"dedicated\",\"service_boundary_arn\":\"arn:b\",\"compute\":{\"ami_parameter\":\"/a\",\"scripts_manifest_parameter\":\"/m\"},\"buckets\":{\"deploy\":\"d\",\"assets\":\"a\"},\"tiers\":{\"private\":{\"listener_arn\":\"l\",\"alb_security_group_id\":\"s\",\"subnet_ids\":[\"a\",\"b\"]}},\"database\":{\"engines\":{}}}"
  }

  assert {
    condition     = jsondecode(output.config_json).database == null && output.provision_function == null
    error_message = "a service with no database is unaffected by which engines run"
  }
}

run "a_name_matching_an_administrator_secret_is_refused" {
  command = plan

  variables {
    service_name = "database-admin-pg"
  }

  expect_failures = [var.service_name]
}

run "a_managed_mongodb_service_uses_the_documentdb_cluster" {
  command = plan

  variables {
    database_engine = "mongodb"
    platform_json   = "{\"schema_version\":1,\"domain_name\":\"example.org\",\"hosting_model\":\"dedicated\",\"service_boundary_arn\":\"arn:b\",\"compute\":{\"ami_parameter\":\"/a\",\"scripts_manifest_parameter\":\"/m\"},\"buckets\":{\"deploy\":\"d\",\"assets\":\"a\"},\"tiers\":{\"private\":{\"listener_arn\":\"l\",\"alb_security_group_id\":\"s\",\"subnet_ids\":[\"a\",\"b\"]}},\"database\":{\"engines\":{\"mongodb\":{\"host\":\"core-production-mongodb.cluster-x.docdb.amazonaws.com\",\"port\":27017,\"provision_function\":\"core-production-mongodb-provision\"}}}}"
  }

  assert {
    condition     = jsondecode(output.config_json).database.host == "core-production-mongodb.cluster-x.docdb.amazonaws.com" && jsondecode(output.config_json).database.port == 27017 && output.provision_function == "core-production-mongodb-provision"
    error_message = "a mongodb service connects to, and is provisioned by, the DocumentDB cluster"
  }
}
