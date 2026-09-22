variable "project_name" {
  type        = string
  description = "Project name. The platform publishes its contract under /<project_name>/platform/config."
}

variable "environment" {
  type        = string
  description = "Environment name (development, staging, production)."
}

variable "service_name" {
  type        = string
  description = "The service's name. Must match the service_name in core's service-roles.json."
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
  description = "The host port the service listens on. Unique per tier."
}

variable "database_engine" {
  type        = string
  default     = null
  description = "The database engine the service uses (postgres or mysql), or null for none. When set, the service's secret gets db_name, db_user and db_password fields."
}

variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path the load balancer checks. The application must answer it without host validation."
}

variable "subdomain" {
  type        = string
  default     = null
  description = "Subdomain under the environment's domain. Defaults to the service name."
}

variable "generated_secret_names" {
  type        = list(string)
  default     = []
  description = "Names of application secrets to generate as random values and store in the service's secret, for example [\"django_secret_key\"]. The application decides what it needs; this repository only generates it."

  validation {
    condition     = alltrue([for name in var.generated_secret_names : can(regex("^[a-z][a-z0-9_]{0,40}$", name))])
    error_message = "Each generated secret name must be lowercase letters, digits and underscores, starting with a letter."
  }

  validation {
    condition     = length(setintersection(toset(var.generated_secret_names), toset(["db_name", "db_user", "db_password"]))) == 0
    error_message = "db_name, db_user and db_password are generated for the database; do not list them."
  }
}

variable "secret_length" {
  type        = number
  default     = 50
  description = "Length of each generated application secret."

  validation {
    condition     = var.secret_length >= 32 && var.secret_length <= 128
    error_message = "secret_length must be between 32 and 128."
  }
}

variable "database_extra_sql_path" {
  type        = string
  default     = null
  description = "Optional path to a file of extra SQL for this service's database (an extension, a schema). It runs as the SERVICE's own user on the service's own database, never as the administrator, and must be safe to run again: provisioning runs on every apply."

  validation {
    condition     = var.database_extra_sql_path == null || fileexists(coalesce(var.database_extra_sql_path, "/dev/null"))
    error_message = "database_extra_sql_path must be a file that exists."
  }
}

variable "image_tag_mutability" {
  type        = string
  default     = "IMMUTABLE"
  description = "ECR tag mutability. IMMUTABLE means a version tag can never be overwritten, which is what makes a rollback trustworthy."
}

variable "lifecycle_image_count" {
  type        = number
  default     = 14
  description = "How many images ECR keeps. Older ones expire, so a rollback further back than this is not possible."
}

# -----------------------------------------------------------------------------
# Dedicated hosts (staging and production)
#
# Ignored where the platform hosts services on a shared fleet.
# -----------------------------------------------------------------------------

variable "instance_types" {
  type        = list(string)
  default     = ["t3.small", "t3a.small"]
  description = "Instance types the service's own hosts may use."
}

variable "min_size" {
  type        = number
  default     = 1
  description = "Fewest hosts."
}

variable "desired_capacity" {
  type        = number
  default     = 2
  description = "Hosts to run in the steady state."
}

variable "max_size" {
  type        = number
  default     = 4
  description = "Most hosts."
}

variable "on_demand_base_capacity" {
  type        = number
  default     = 1
  description = "Hosts that are always on demand. Keep at least one: a spot interruption taking every host at once would otherwise take the service down."
}

variable "on_demand_percentage_above_base_capacity" {
  type        = number
  default     = 0
  description = "Percentage of the capacity above the base that is on demand."
}

variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB on each host."
}
