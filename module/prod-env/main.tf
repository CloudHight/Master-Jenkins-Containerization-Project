#prod security group
resource "aws_security_group" "prod-sg" {
  name        = "${var.name}-prod-sg"
  description = "prod Security group"
  vpc_id      = var.vpc-id
  ingress {
    description     = "SSH access from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion, var.ansible]
  }

  ingress {
    description     = "HTTP access from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.prod-elb-sg.id]
  }
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.name}-prod-sg"
  }
}
data "aws_ami" "redhat" {
  most_recent = true
  owners      = ["309956199498"] # RedHat's owner ID
  filter {
    name   = "name"
    values = ["RHEL-9*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
# Create Launch Template
resource "aws_launch_template" "prod_lnch_tmpl" {
  image_id      = data.aws_ami.redhat.id
  name_prefix   = "${var.name}-prod-web-tmpl"
  instance_type = "t2.medium"
  key_name      = var.key-name
  user_data = base64encode(join("\n", [
    "#!/bin/bash",
    "AWS_REGION=${var.region}",
    "CW_CONFIG_PARAM=${var.cw_config_param}",
    file("${path.module}/../common/bootstrap.sh"),
    templatefile("${path.module}/docker-script.sh", {
      nexus_registry  = var.nexus_registry,
      nexus_secret_id = var.nexus_secret_arn,
      region          = var.region
    }),
  ]))
  iam_instance_profile {
    name = aws_iam_instance_profile.prod.name
  }
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  network_interfaces {
    security_groups = [aws_security_group.prod-sg.id]
  }
  metadata_options {
    http_tokens = "required"
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "prod_autoscaling_grp" {
  name                      = "${var.name}-prod-asg"
  max_size                  = 3
  min_size                  = 1
  desired_capacity          = 1
  health_check_grace_period = 120
  health_check_type         = "EC2"
  force_delete              = true
  launch_template {
    id      = aws_launch_template.prod_lnch_tmpl.id
    version = "$Latest"
  }
  vpc_zone_identifier = [var.pri-subnet1, var.pri-subnet2]
  target_group_arns   = [aws_lb_target_group.prod-target-group.arn]

  tag {
    key                 = "Name"
    value               = "${var.name}-prod-asg"
    propagate_at_launch = true
  }
}
# Created autoscaling group policy
resource "aws_autoscaling_policy" "prod-asg-policy" {
  name                   = "asg-policy"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.prod_autoscaling_grp.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# Create Application Load Balancer for prod
resource "aws_lb" "prod_LB" {
  name                       = "${var.name}-prod-LB"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.prod-elb-sg.id]
  subnets                    = [var.pub-subnet1, var.pub-subnet2]
  drop_invalid_header_fields = true
  tags = {
    Name = "${var.name}-prod-LB"
  }
}
#prod-elb security group
resource "aws_security_group" "prod-elb-sg" {
  name        = "${var.name}-prod-elb-sg"
  description = "prod-elb Security group"
  vpc_id      = var.vpc-id
  ingress {
    description = "HTTP (redirected to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS from the internet (via WAF)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.name}-prod-elb-sg"
  }
}

#Create Target group for load Balancer
resource "aws_lb_target_group" "prod-target-group" {
  name        = "${var.name}-prod-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc-id
  target_type = "instance"
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 5
    path                = "/"
  }
  tags = {
    Name = "${var.name}-prod-tg"
  }
}

# Create load balance listener for http
resource "aws_lb_listener" "prod_load_balancer_listener_http" {
  load_balancer_arn = aws_lb.prod_LB.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
# Create load balance listener for https
resource "aws_lb_listener" "prod_load_balancer_listener_https" {
  load_balancer_arn = aws_lb.prod_LB.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm-cert-arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod-target-group.arn
  }
}
# Create Route 53 record for prod server
data "aws_route53_zone" "team2-acp-zone" {
  name         = var.domain
  private_zone = false
}

# Create Route 53 record for prod server
resource "aws_route53_record" "prod-record" {
  zone_id = data.aws_route53_zone.team2-acp-zone.zone_id
  name    = "prod.${var.domain}"
  type    = "A"
  alias {
    name                   = aws_lb.prod_LB.dns_name
    zone_id                = aws_lb.prod_LB.zone_id
    evaluate_target_health = true
  }
}

# IAM role for the prod servers: SSM access, CloudWatch agent, read the Nexus + DB secrets
resource "aws_iam_role" "prod" {
  name = "${var.name}-prod-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "prod_ssm" {
  role       = aws_iam_role.prod.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "prod_cw_agent" {
  role       = aws_iam_role.prod.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "prod_secrets" {
  name = "${var.name}-prod-secrets"
  role = aws_iam_role.prod.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = [var.nexus_secret_arn, var.db_secret_arn]
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "prod" {
  name = "${var.name}-prod-profile"
  role = aws_iam_role.prod.name
}
