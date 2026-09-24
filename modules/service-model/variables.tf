variable "project_name" {
  type        = string
  description = "Project name."
}

variable "environment" {
  type        = string
  description = "Environment name (development, staging, production)."
}

variable "service_name" {
  type        = string
  description = "The service's name. It names the service's ECR repository, secret, target group and S3 prefixes, and must match the service_name in core's service-roles.json."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-22 lowercase letters, digits or hyphens, starting with a letter."
  }

  # The platform's own resources use these names; a service called one of them
  # could generate a resource name that collides with core's.
  validation {
    condition     = !contains(["database", "database-hub", "fleet", "internal", "platform", "private", "services"], var.service_name)
    error_message = "service_name must not be one of the names the platform itself uses: database, database-hub, fleet, internal, platform, private, services."
  }

  # Service secrets are scoped by name prefix, <project>-<service>-<environment>*.
  # Core names its database secrets <project>-database-<something>-... (each
  # engine's administrator, the platform list's passwords), so a service whose
  # name begins database- could match one. Core refuses it too.
  validation {
    condition     = !startswith(var.service_name, "database-")
    error_message = "service_name must not begin with database-: core's database secrets are named that way."
  }
}

variable "service_type" {
  type        = string
  description = "What kind of service this is (web, api, worker, ...). Part of the ECR repository name: <service_name>/<service_type>."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,15}$", var.service_type))
    error_message = "service_type must be 1-16 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "tier" {
  type        = string
  description = "Which tier of the shared fleet the service runs on: private or internal."

  validation {
    condition     = contains(["private", "internal"], var.tier)
    error_message = "tier must be \"private\" or \"internal\"."
  }
}

variable "service_port" {
  type        = number
  description = "The host port the service listens on. Services share a host on the shared fleet, so it must be unique per tier; the container itself always listens on its own port."

  validation {
    condition     = var.service_port == floor(var.service_port) && var.service_port >= 1024 && var.service_port <= 65535
    error_message = "service_port must be a whole number from 1024 to 65535."
  }
}

variable "database_engine" {
  type        = string
  default     = null
  description = "The database engine the service uses (postgres, mysql or mongodb), or null for none. The environment must run it: development runs what the database engines repository activates, staging and production what core lists in their database_engines."

  validation {
    condition     = var.database_engine == null || contains(["postgres", "mysql", "mongodb"], coalesce(var.database_engine, "x"))
    error_message = "database_engine must be \"postgres\", \"mysql\", \"mongodb\" or null."
  }
}

variable "agents" {
  type = map(object({
    email  = string
    access = string
  }))
  default     = {}
  description = "The service team's own people, from infrastructure/<environment>/agents.json. Each gets a database login, <service>.<name> (the service's database name, a dot, the name), on this service's database only, with access \"read\" (look at and query data) or \"write\" (also add, change and delete rows); and, where the platform has a front door, a sign-in to the team tools. In production core allows write only for logins it has approved."

  validation {
    condition     = alltrue([for name in keys(var.agents) : can(regex("^[a-z][a-z0-9]{1,19}$", name))])
    error_message = "Each agent's name must be 2-20 lowercase letters and digits, starting with a letter."
  }

  validation {
    condition     = alltrue([for agent in values(var.agents) : contains(["read", "write"], agent.access)])
    error_message = "Each agent's access must be \"read\" or \"write\"."
  }

  validation {
    condition     = alltrue([for agent in values(var.agents) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", agent.email))])
    error_message = "Each agent needs a valid email address: their sign-in to the team tools, and where the invitation goes."
  }

  validation {
    condition     = length(distinct([for agent in values(var.agents) : lower(agent.email)])) == length(var.agents)
    error_message = "Two agents share an email address."
  }
}

variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path the load balancer checks. The application must answer it without host validation."

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must begin with '/'."
  }
}

variable "subdomain" {
  type        = string
  default     = null
  description = "Subdomain the service is served on, under the environment's domain. Defaults to the service name."

  validation {
    condition     = var.subdomain == null || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", coalesce(var.subdomain, "x")))
    error_message = "subdomain must be lowercase letters, digits and hyphens."
  }
}

variable "platform_json" {
  type        = string
  description = "The platform contract: the JSON in the SSM parameter /<project>/platform/config."
}

# ------------------------------------------------------------------------------
# Known only after the resources exist; they go into the service config parameter.
# ------------------------------------------------------------------------------

variable "secret_arn" {
  type        = string
  default     = null
  description = "ARN of the service's secret."
}

variable "secret_name" {
  type        = string
  default     = null
  description = "Name of the service's secret."
}

variable "target_group_arn" {
  type        = string
  default     = null
  description = "ARN of the service's target group."
}

variable "ecr_repository_url" {
  type        = string
  default     = null
  description = "URL of the service's ECR repository."
}

variable "ecr_repository_name" {
  type        = string
  default     = null
  description = "Name of the service's ECR repository."
}
