output "ansible_ip" {
  value = aws_instance.ansible-server.private_ip
}
output "ansible_sg" {
  value = aws_security_group.ansible-security-group.id
}

output "instance_id" {
  value = aws_instance.ansible-server.id
}
