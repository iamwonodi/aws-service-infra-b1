# The golden AMI core built for this environment. Read as a data source rather
# than copied into a variable: core rebuilding the image changes this parameter,
# which gives a new launch template version on the next plan, which the group
# then rolls out.
data "aws_ssm_parameter" "ami" {
  name = var.ami_parameter
}

data "aws_iam_policy_document" "instance_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# What the hosts may do. The permissions boundary caps all of it, so this
# document cannot grant more than the platform allows however it is written.
data "aws_iam_policy_document" "instance" {
  statement {
    sid    = "SsmAgent"
    effect = "Allow"

    actions = [
      "ec2messages:AcknowledgeMessage", "ec2messages:DeleteMessage", "ec2messages:FailMessage",
      "ec2messages:GetEndpoint", "ec2messages:GetMessages", "ec2messages:SendReply",
      "ssm:DescribeDocument", "ssm:GetDocument", "ssm:ListAssociations",
      "ssm:ListInstanceAssociations", "ssm:PutInventory", "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel",
    ]

    resources = ["*"]
  }

  statement {
    sid       = "PullImages"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "PullOwnImages"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources = ["arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.service_name}/*"]
  }

  # Core's scripts, and the manifest that proves they are core's.
  statement {
    sid       = "ReadPlatformScripts"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.platform_deploy_bucket}/${var.platform_prefix}/*"]
  }

  statement {
    sid       = "ListPlatformScripts"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.platform_deploy_bucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.platform_prefix, "${var.platform_prefix}/*"]
    }
  }

  # This service's own configuration, and nothing else.
  statement {
    sid       = "ReadOwnConfiguration"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.config_bucket}/*"]
  }

  statement {
    sid       = "ListOwnConfiguration"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.config_bucket}"]
  }

  statement {
    sid     = "ReadPublishedParameters"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]

    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.scripts_manifest_parameter}",
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/platform/*",
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/services/${var.service_name}/*",
    ]
  }

  # Its own secret, resolved on the host just before the container starts.
  statement {
    sid       = "ReadOwnSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.secret_prefix}-secret-vault-*"]
  }
}

data "aws_caller_identity" "current" {}
