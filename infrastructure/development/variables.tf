variable "project_name" {
  type        = string
  description = "Project name. Must match the project the platform (core) was set up with."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-16 lowercase letters, digits or hyphens, starting with a letter. If it is still the CHANGE_ME placeholder, run scripts/init-service.sh."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS Region of this environment. Keep it in sync with backend.tf by hand (backend blocks cannot use variables); scripts/init-service.sh sets both."
}

variable "service_name" {
  type        = string
  description = "The service's name. Must match the service_name in core's service-roles.json. It names the ECR repository, secret, target group, S3 prefixes and state key."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-22 lowercase letters, digits or hyphens, starting with a letter. If it is still the CHANGE_ME placeholder, run scripts/init-service.sh."
  }
}

variable "service_type" {
  type        = string
  description = "What kind of service this is (web, api, worker, ...). Part of the ECR repository name."
}

variable "tier" {
  type        = string
  description = "Which tier of the shared fleet the service runs on: private or internal."
}

variable "service_port" {
  type        = number
  description = "The host port the service listens on. Unique per tier: services share a host."
}

variable "database_engine" {
  type        = string
  default     = null
  description = "The database engine the service uses (postgres, mysql or mongodb), or null for none. The environment must run it."
}

variable "database_extra_sql_path" {
  type        = string
  default     = null
  description = "Optional path to a file of extra SQL for this service's database. It runs as the service's own user on its own database, and must be safe to run again."
}

variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path the load balancer checks."
}

variable "subdomain" {
  type        = string
  default     = null
  description = "Subdomain under the environment's domain. Defaults to the service name."
}

variable "generated_secret_names" {
  type        = list(string)
  default     = []
  description = "Names of application secrets to generate as random values, for example [\"django_secret_key\"]."
}
