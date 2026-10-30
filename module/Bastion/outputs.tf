output "bastion_sg" {
  value = aws_security_group.bastion-security-group.id
}
data "aws_instances" "bastion_instances" {
  filter {
    name   = "tag:Name"
    values = ["${var.name}-bastion-asg"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
  depends_on = [aws_autoscaling_group.bastion-asg]
}
output "bastion_public_ip" {
  value       = data.aws_instances.bastion_instances.public_ips[0]
  description = "The public IP address of the bastion instance"
}

output "asg_name" {
  value = aws_autoscaling_group.bastion-asg.name
}
