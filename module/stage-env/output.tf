output "stage_sg" {
  value       = aws_security_group.stage-security-group.id
  description = "Security group ID for the stage environment"
}

output "alb_arn" {
  value = aws_lb.stage_LoadBalancer.arn
}

output "alb_arn_suffix" {
  value = aws_lb.stage_LoadBalancer.arn_suffix
}

output "tg_arn_suffix" {
  value = aws_lb_target_group.stage-target-group.arn_suffix
}

output "asg_name" {
  value = aws_autoscaling_group.stage_autoscaling_group.name
}
