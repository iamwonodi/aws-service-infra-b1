provider "aws" {
  region = var.aws_region

  # Service is required, not decorative: core's policy lets this repository's
  # role tag and change only resources whose Service tag names this service.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "development"
      Service     = var.service_name
      ManagedBy   = "terraform"
    }
  }
}
