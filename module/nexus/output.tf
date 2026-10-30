output "nexus_ip" {
  value = aws_instance.nexus-server.private_ip
}

output "nexus_registry" {
  value = "nexus.${var.domain_name}:8085"
}

output "instance_id" {
  value = aws_instance.nexus-server.id
}

output "alb_arn" {
  value = aws_lb.nexus.arn
}

output "alb_arn_suffix" {
  value = aws_lb.nexus.arn_suffix
}

output "tg_arn_suffix" {
  value = aws_lb_target_group.nexus.arn_suffix
}

output "docker_tg_arn_suffix" {
  value = aws_lb_target_group.docker.arn_suffix
}
