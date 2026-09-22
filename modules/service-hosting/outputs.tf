output "autoscaling_group_name" {
  description = "Name of the service's auto scaling group."
  value       = module.autoscaling_group.name
}

output "autoscaling_group_arn" {
  description = "ARN of the service's auto scaling group."
  value       = module.autoscaling_group.arn
}

output "security_group_id" {
  description = "The hosts' security group. Only the tier's load balancer may reach it."
  value       = aws_security_group.instance.id
}

output "instance_role_arn" {
  description = "ARN of the role the hosts run as. It carries the platform's permissions boundary."
  value       = aws_iam_role.instance.arn
}

output "instance_profile_name" {
  description = "Instance profile the hosts run as."
  value       = aws_iam_instance_profile.instance.name
}

output "config_bucket_name" {
  description = "Bucket the application repository publishes into, and the hosts read from."
  value       = module.config_bucket.bucket_id
}

output "update_document_name" {
  description = "SSM document that redeploys the hosts. The application repository sends this, and nothing else."
  value       = aws_ssm_document.update.name
}

output "launch_template_id" {
  description = "ID of the launch template the group uses."
  value       = module.launch_template.id
}
