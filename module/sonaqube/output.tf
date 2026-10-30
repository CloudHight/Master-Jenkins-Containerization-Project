output "instance_id" {
  value = aws_instance.sonarqube-server.id
}

output "alb_arn" {
  value = aws_lb.sonarqube.arn
}

output "alb_arn_suffix" {
  value = aws_lb.sonarqube.arn_suffix
}

output "tg_arn_suffix" {
  value = aws_lb_target_group.sonarqube.arn_suffix
}
