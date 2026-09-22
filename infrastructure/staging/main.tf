module "service" {
  source = "../../modules/service"

  project_name = var.project_name
  environment  = "staging"
  service_name = var.service_name
  service_type = var.service_type
  tier         = var.tier
  service_port = var.service_port

  database_engine         = var.database_engine
  database_extra_sql_path = var.database_extra_sql_path
  health_check_path       = var.health_check_path
  subdomain               = var.subdomain
  generated_secret_names  = var.generated_secret_names

  # This environment hosts services dedicated: the service creates its own hosts.
  # Where they go comes from the platform contract; their shape is set here.
  instance_types                           = var.instance_types
  min_size                                 = var.min_size
  desired_capacity                         = var.desired_capacity
  max_size                                 = var.max_size
  on_demand_base_capacity                  = var.on_demand_base_capacity
  on_demand_percentage_above_base_capacity = var.on_demand_percentage_above_base_capacity
  root_volume_size                         = var.root_volume_size
}
