locals {
  # <project>-<environment>-<service>: what this module names itself.
  name = "${var.project_name}-${var.environment}-${var.service_name}"

  # The service's secret is named by terraform-aws-secrets-vault v1, which puts the
  # service before the environment. The instance role may read exactly that name.
  # It follows the rule above once the module releases a v2.
  secret_prefix = "${var.project_name}-${var.service_name}-${var.environment}"

  # Core's generated policy lets this repository create IAM roles only under this
  # path, and only carrying the boundary and this tag.
  iam_path = "/services/${var.service_name}/"

  update_document_name = "${var.project_name}-${var.service_name}-update"

  application_root = "/opt/applications"

  # A dedicated host syncs one prefix, exactly as a shared fleet host does. Its
  # "tier" is services/, under which only this service has a directory -- so the
  # deploy engine core owns needs no change to run here.
  fleet_tier = "services"

  # Service is not decoration: core's policy lets this role's resources be created
  # and changed only while they carry it.
  tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      Service     = var.service_name
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}
