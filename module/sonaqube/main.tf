
# Creating security group for SonarQube (private - only reachable from the ALB)
resource "aws_security_group" "sonarqube-sg" {
  name        = "${var.name}-sonarqube-sg"
  description = "Allow inbound traffic from lb and all outbound traffic"
  vpc_id      = var.vpc

  # Ingress rule: Allow SonarQube web UI (port 9000) from loadbalancer sg
  ingress {
    description     = "SonarQube Web UI (port 9000)"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.lb-sg.id]
  }

  # Egress rule: Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # All protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow outbound to anywhere
  }

  tags = {
    Name = "${var.name}-sonarqube-sg"
  }
}

# Creating security group for LoadBalancer
resource "aws_security_group" "lb-sg" {
  name        = "${var.name}-sonarqube-lb-sg"
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
  # Egress rule: Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # All protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow outbound to anywhere
  }

  tags = {
    Name = "${var.name}-sonarqube-lb-sg"
  }
}
# Data source to get the latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

# Create Sonarqube Server
resource "aws_instance" "sonarqube-server" {
  ami                         = data.aws_ami.ubuntu.id #ubuntu
  instance_type               = "t2.medium"
  vpc_security_group_ids      = [aws_security_group.sonarqube-sg.id]
  key_name                    = var.keypair
  subnet_id                   = var.subnet_id
  iam_instance_profile        = aws_iam_instance_profile.sonarqube_profile.name
  associate_public_ip_address = false
  # user_data only runs on first boot, so rebuild the server when the install script changes
  user_data_replace_on_change = true
  user_data = join("\n", [
    "#!/bin/bash",
    "AWS_REGION=${var.region}",
    "CW_CONFIG_PARAM=${var.cw_config_param}",
    "SONAR_DB_SECRET_ID=${var.sonar_db_secret_arn}",
    file("${path.module}/../common/bootstrap.sh"),
    file("${path.module}/sonarqube.sh"),
  ])
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = var.kms_key_arn
  }
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name   = "${var.name}-sonarqube-server"
    Backup = var.name
  }
}

# Create Application Load Balancer for sonarqube (protected by WAF)
resource "aws_lb" "sonarqube" {
  name                       = "${var.name}-sonarqube-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.lb-sg.id]
  subnets                    = var.subnets
  drop_invalid_header_fields = true
  tags = {
    Name = "${var.name}-sonarqube-alb"
  }
}

resource "aws_lb_target_group" "sonarqube" {
  name     = "${var.name}-sonarqube-tg"
  port     = 9000
  protocol = "HTTP"
  vpc_id   = var.vpc
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    path                = "/api/system/status"
  }
  tags = {
    Name = "${var.name}-sonarqube-tg"
  }
}

resource "aws_lb_target_group_attachment" "sonarqube" {
  target_group_arn = aws_lb_target_group.sonarqube.arn
  target_id        = aws_instance.sonarqube-server.id
  port             = 9000
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.sonarqube.arn
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
  load_balancer_arn = aws_lb.sonarqube.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sonarqube.arn
  }
}

# Create a DNS record for the ALB
resource "aws_route53_record" "sonarqube" {
  zone_id = var.hosted_zone_id
  name    = "sonarqube.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.sonarqube.dns_name
    zone_id                = aws_lb.sonarqube.zone_id
    evaluate_target_health = true
  }

}

# create an IAM instance role
resource "aws_iam_role" "sonarqube-role" {
  name = "${var.name}-sonarqube-role"

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
    Name = "${var.name}-sonarqube-role"
  }
}

# sonarqube IAM profile
resource "aws_iam_instance_profile" "sonarqube_profile" {
  name = "${var.name}-sonarqube-profile"
  role = aws_iam_role.sonarqube-role.name
}

# SSM permission (Session Manager access instead of SSH)
resource "aws_iam_role_policy_attachment" "ssm_access" {
  role       = aws_iam_role.sonarqube-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent permission
resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.sonarqube-role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Read only the SonarQube DB secret
resource "aws_iam_role_policy" "secrets" {
  name = "${var.name}-sonarqube-secrets"
  role = aws_iam_role.sonarqube-role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.sonar_db_secret_arn
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.kms_key_arn
      }
    ]
  })
}
