output "service_config_parameter" {
  description = "SSM parameter the application repository reads."
  value       = aws_ssm_parameter.service_config.name
}

output "domain" {
  description = "The domain the service is served on."
  value       = module.model.domain
}

output "ecr_repository_url" {
  description = "Where the application repository pushes its images."
  value       = module.repository.repository_url
}

output "secret_arn" {
  description = "ARN of the service's secret."
  value       = module.vault.secret_arn
}

output "target_group_arn" {
  description = "ARN of the service's target group."
  value       = module.target_group.arn
}

output "provision_document" {
  description = "SSM document the apply workflow sends to create this service's database and user. Null for a service without a database."
  value       = module.model.provision_document
}

output "service_name" {
  description = "The service's name, as the provisioning document's parameter."
  value       = var.service_name
}

output "provision_function" {
  description = "Lambda the apply workflow invokes to create this service's database and user on a managed database. Null where provisioning goes through the EC2 host's document, or there is no database."
  value       = module.model.provision_function
}
