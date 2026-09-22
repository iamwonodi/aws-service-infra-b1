output "platform" {
  description = "The decoded platform contract."
  value       = local.platform

  depends_on = [terraform_data.model_invariants]
}

output "tier" {
  description = "The platform's resources for the service's tier: listener_arn, alb_security_group_id, security_group_id, asg_name."
  value       = local.tier

  depends_on = [terraform_data.model_invariants]
}

output "domain" {
  description = "The domain the service is served on."
  value       = local.domain
}

output "target_group_name" {
  description = "The name the target group module will generate."
  value       = local.target_group_name
}

output "parameter_name" {
  description = "SSM parameter the service's application repository reads."
  value       = local.parameter_name
}

output "config_json" {
  description = "The service config document (see docs/service-config.md)."
  value       = local.config_json

  depends_on = [terraform_data.model_invariants]
}

output "database_identifier" {
  description = "Database and user name for the service (its name with underscores)."
  value       = local.database_identifier
}

output "database_port_parameter" {
  description = "SSM parameter holding the database engine's port on the EC2 host. Null without a database, and on a managed database, whose port the contract publishes directly."
  value       = local.database_port_parameter
}

output "provision_document" {
  description = "SSM document that creates this service's database and user, or null when the platform has no database host to provision on."
  value       = local.provision_document
}

output "provisioning_prefix" {
  description = "Where this service publishes its provisioning request in the deploy bucket."
  value       = local.provisioning_prefix
}

output "provisioning_request_json" {
  description = "The provisioning request core's script reads: which service, which engine, and where its credentials are. It holds no credential itself."
  value       = local.provisioning_request_json
}

output "is_dedicated" {
  description = "True where this service creates its own hosts rather than sharing the tier's fleet."
  value       = local.is_dedicated
}

output "config_bucket" {
  description = "Bucket a dedicated service publishes into, and its hosts read from."
  value       = local.config_bucket
}

output "update_document_name" {
  description = "SSM document that redeploys a dedicated service's own hosts."
  value       = local.update_document_name
}

output "ami_parameter" {
  description = "SSM parameter holding the golden AMI's ID. Read at plan time, so a rebuild by core reaches this service on its next plan."
  value       = local.ami_parameter
}

output "scripts_manifest_parameter" {
  description = "SSM parameter a host verifies the platform scripts against."
  value       = local.scripts_manifest_parameter
}

output "platform_prefix" {
  description = "Prefix in the platform's deploy bucket that holds the scripts a host installs."
  value       = local.platform_prefix
}

output "shared_deploy_bucket" {
  description = "The platform's own deploy bucket, which holds the platform scripts."
  value       = local.shared_deploy_bucket
}

output "service_boundary_arn" {
  description = "Permissions boundary every IAM role this repository creates must carry."
  value       = try(local.platform.service_boundary_arn, null)
}

output "provision_function" {
  description = "Lambda that creates this service's database and user on a managed database, or null where the platform provisions through the EC2 host's document instead."
  value       = local.provision_function
}
