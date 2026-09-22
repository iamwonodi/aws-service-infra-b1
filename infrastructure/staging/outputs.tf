output "service_config_parameter" {
  description = "SSM parameter the application repository reads to deploy the service."
  value       = module.service.service_config_parameter
}

output "domain" {
  description = "The domain the service is served on."
  value       = module.service.domain
}

output "ecr_repository_url" {
  description = "Where the application repository pushes its images."
  value       = module.service.ecr_repository_url
}

output "secret_arn" {
  description = "ARN of the service's secret."
  value       = module.service.secret_arn
}

output "provision_document" {
  description = "SSM document the apply workflow sends to create the service's database and user. Null for a service without a database."
  value       = module.service.provision_document
}

output "provision_function" {
  description = "Lambda the apply workflow invokes to create the service's database and user on a managed database. Null otherwise."
  value       = module.service.provision_function
}
