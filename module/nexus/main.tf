
# Creating security group for Nexus (private - only reachable from the ALB)
resource "aws_security_group" "Nexus-security-group" {
  name        = "${var.name}-Nexus-sg"
  description = "Allow inbound traffic from lb and all outbound traffic"
  vpc_id      = var.vpc

  # Ingress rule: Allow Nexus UI (port 8081) from loadbalancer sg
  ingress {
    description     = "Nexus (port 8081)"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.lb-security-group.id]
  }

  # Ingress rule: Allow Docker registry (port 8085) from loadbalancer sg
  ingress {
    description     = "Docker registry (port 8085)"
    from_port       = 8085
    to_port         = 8085
    protocol        = "tcp"
    security_groups = [aws_security_group.lb-security-group.id]
  }

  # Egress rule: Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # All protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow outbound to anywhere
  }

  tags = {
    Name = "${var.name}-Nexus-sg"
  }
}

# Creating security group for LoadBalancer
resource "aws_security_group" "lb-security-group" {
  name        = "${var.name}-lb-sg"
  description = "Allow inbound traffic for lb and all outbound traffic"
  vpc_id      = var.vpc

  # Ingress rule: HTTP (redirected to HTTPS)
  ingress {
    description = "HTTP (port 80)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress rule: Allow HTTPS (port 443)
  ingress {
    description = "HTTPS (port 443)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress rule: Allow Docker registry over TLS (port 8085)
  ingress {
    description = "Docker registry HTTPS (port 8085)"
    from_port   = 8085
    to_port     = 8085
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress rule: Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # All protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow outbound to anywhere
  }

  tags = {
    Name = "${var.name}-lb-sg"
  }
}

# Create Application Load Balancer for nexus (protected by WAF)
resource "aws_lb" "nexus" {
  name                       = "${var.name}-nexus-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.lb-security-group.id]
  subnets                    = var.subnets
  drop_invalid_header_fields = true
  tags = {
    Name = "${var.name}-nexus-alb"
  }
}

# Target group for the Nexus UI
resource "aws_lb_target_group" "nexus" {
  name     = "${var.name}-nexus-tg"
  port     = 8081
  protocol = "HTTP"
  vpc_id   = var.vpc
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    path                = "/service/rest/v1/status"
  }
  tags = {
    Name = "${var.name}-nexus-tg"
  }
}

# Target group for the Docker registry connector
resource "aws_lb_target_group" "docker" {
  name     = "${var.name}-nexus-docker-tg"
  port     = 8085
  protocol = "HTTP"
  vpc_id   = var.vpc
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    path                = "/v2/"
    matcher             = "200,401"
  }
  tags = {
    Name = "${var.name}-nexus-docker-tg"
  }
}

resource "aws_lb_target_group_attachment" "nexus" {
  target_group_arn = aws_lb_target_group.nexus.arn
  target_id        = aws_instance.nexus-server.id
  port             = 8081
}

resource "aws_lb_target_group_attachment" "docker" {
  target_group_arn = aws_lb_target_group.docker.arn
  target_id        = aws_instance.nexus-server.id
  port             = 8085
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.nexus.arn
  port              = 80
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

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.nexus.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nexus.arn
  }
}

# Docker registry: nexus.<domain>:8085 (TLS terminated at the ALB)
resource "aws_lb_listener" "docker" {
  load_balancer_arn = aws_lb.nexus.arn
  port              = 8085
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.docker.arn
  }
}

# Create a DNS record for the ALB
resource "aws_route53_record" "nexus" {
  zone_id = var.hosted_zone_id
  name    = "nexus.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.nexus.dns_name
    zone_id                = aws_lb.nexus.zone_id
    evaluate_target_health = true
  }
}
# create an IAM instance role
resource "aws_iam_role" "nexus-role" {
  name = "${var.name}-nexus-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "${var.name}-nexus-role"
  }
}

# nexus IAM profile
resource "aws_iam_instance_profile" "nexus_profile" {
  name = "${var.name}-nexus-profile"
  role = aws_iam_role.nexus-role.name
}

# SSM permission (Session Manager access instead of SSH)
resource "aws_iam_role_policy_attachment" "ssm_access" {
  role       = aws_iam_role.nexus-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent permission
resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.nexus-role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Read only the Nexus admin secret
resource "aws_iam_role_policy" "secrets" {
  name = "${var.name}-nexus-secrets"
  role = aws_iam_role.nexus-role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.nexus_secret_arn
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.kms_key_arn
      }
    ]
  })
}

# Data source to get the latest red-hat AMI
data "aws_ami" "centos" {
  most_recent = true
  owners      = ["125523088429"] # Verified CentOS image owner (check regionally!)

  filter {
    name   = "name"
    values = ["CentOS Stream 9*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create Nexus Server
resource "aws_instance" "nexus-server" {
  ami                         = data.aws_ami.centos.id #centOs stream_9
  instance_type               = "t2.medium"
  vpc_security_group_ids      = [aws_security_group.Nexus-security-group.id]
  key_name                    = var.keypair
  subnet_id                   = var.subnet_id
  iam_instance_profile        = aws_iam_instance_profile.nexus_profile.name
  associate_public_ip_address = false
  user_data = join("\n", [
    "#!/bin/bash",
    "AWS_REGION=${var.region}",
    "CW_CONFIG_PARAM=${var.cw_config_param}",
    "NEXUS_SECRET_ID=${var.nexus_secret_arn}",
    file("${path.module}/../common/bootstrap.sh"),
    file("${path.module}/nexus.sh"),
  ])
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = var.kms_key_arn
  }
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name   = "${var.name}-nexus-server"
    Backup = var.name
  }
}
