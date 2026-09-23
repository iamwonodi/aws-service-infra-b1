variable "project_name" {
  type        = string
  description = "Project name. Part of every resource's name."
}

variable "environment" {
  type        = string
  description = "Environment name. Part of every resource's name."
}

variable "service_name" {
  type        = string
  description = "The service these hosts run. Core's policy scopes this repository's permissions to resources carrying it."
}

variable "service_port" {
  type        = number
  description = "Port the service listens on. The load balancer reaches the hosts on it."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary every IAM role created here must carry. Core's policy refuses to create a role without it, so this is not optional."
}

variable "ami_parameter" {
  type        = string
  description = "SSM parameter holding core's golden AMI ID. Read at plan time, so a rebuild by core produces a new launch template version on the next plan."
}

variable "scripts_manifest_parameter" {
  type        = string
  description = "SSM parameter a host verifies the platform scripts against before installing them."
}

variable "platform_deploy_bucket" {
  type        = string
  description = "Core's deploy bucket, which holds the platform scripts under its reserved prefix."
}

variable "platform_prefix" {
  type        = string
  default     = "_platform"
  description = "Prefix in that bucket holding the scripts. A host may read this and nothing else in core's bucket."
}

variable "config_bucket" {
  type        = string
  description = "This service's own bucket. Its application repository publishes the compose file and .env here; these hosts read them."
}

variable "vpc_id" {
  type        = string
  description = "VPC the hosts run in."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the hosts run in: the tier's own."
}

variable "alb_security_group_id" {
  type        = string
  description = "The tier's load balancer. It is the only thing allowed to reach the service's port."
}

variable "tier_security_group_id" {
  type        = string
  description = "The tier's own security group. The hosts wear it beside their own, because the databases and the Secrets Manager endpoint admit it. It has no inbound rules, so it opens nothing on the hosts."

  validation {
    condition     = trimspace(var.tier_security_group_id) != ""
    error_message = "tier_security_group_id must not be empty."
  }
}

variable "ecr_registry_url" {
  type        = string
  description = "Registry the hosts pull the service's image from."
}

variable "aws_region" {
  type        = string
  description = "AWS Region. The hosts' scripts use it for every API call."
}

# -----------------------------------------------------------------------------
# Capacity
# -----------------------------------------------------------------------------

variable "instance_types" {
  type        = list(string)
  default     = ["t3.small", "t3a.small"]
  description = "Instance types the group may use. More than one widens the pool a spot request can draw from."
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
  description = "Hosts that are always on demand. The rest follow on_demand_percentage_above_base_capacity. Keep at least one: a spot interruption that took every host at once would otherwise take the service down."
}

variable "on_demand_percentage_above_base_capacity" {
  type        = number
  default     = 0
  description = "Percentage of the capacity above the base that is on demand. 0 makes every host beyond the base a spot instance."
}

variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB. It holds the container images as well as the operating system."
}

variable "health_check_grace_period" {
  type        = number
  default     = 300
  description = "Seconds before a new host's load balancer health is allowed to matter. It must exceed the time to fetch the scripts, pull the image and start the container."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource this module creates."
}

variable "target_group_arns" {
  type        = list(string)
  default     = []
  description = "Target groups the hosts serve. This configuration creates both the group and the target group, so it owns the attachment."
}
