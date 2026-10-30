output "prod_sg" {
  value       = aws_security_group.prod-sg.id
  description = "Security group ID for the prod environment"
}

output "alb_arn" {
  value = aws_lb.prod_LB.arn
}

output "alb_arn_suffix" {
  value = aws_lb.prod_LB.arn_suffix
}

output "tg_arn_suffix" {
  value = aws_lb_target_group.prod-target-group.arn_suffix
}

output "asg_name" {
  value = aws_autoscaling_group.prod_autoscaling_grp.name
}
