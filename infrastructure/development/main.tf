module "service" {
  source = "../../modules/service"

  project_name = var.project_name
  environment  = "development"
  service_name = var.service_name
  service_type = var.service_type
  tier         = var.tier
  service_port = var.service_port

  database_engine         = var.database_engine
  database_extra_sql_path = var.database_extra_sql_path
  health_check_path       = var.health_check_path
  subdomain               = var.subdomain
  generated_secret_names  = var.generated_secret_names
}
