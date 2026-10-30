locals {
  name = "jenkins-team1"
}

data "aws_caller_identity" "current" {}

resource "aws_vpc" "vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  tags = {
    Name = "${local.name}-vpc"
  }
}
# create public subnet 1 (ALB + NAT gateway)
resource "aws_subnet" "pub_sub" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-3a"

  tags = {
    Name = "${local.name}-pub-sub"
  }
}
# create public subnet 2 (an ALB needs two AZs)
resource "aws_subnet" "pub_sub2" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-west-3b"

  tags = {
    Name = "${local.name}-pub-sub2"
  }
}
# create private subnet for jenkins
resource "aws_subnet" "pri_sub" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-3a"

  tags = {
    Name = "${local.name}-pri-sub"
  }
}
# create internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.name}-igw"
  }
}
# Create route table for public subnets
resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${local.name}-pub-rt"
  }
}
resource "aws_route_table_association" "associate_public_subnet" {
  subnet_id      = aws_subnet.pub_sub.id
  route_table_id = aws_route_table.public-rt.id
}
resource "aws_route_table_association" "associate_public_subnet2" {
  subnet_id      = aws_subnet.pub_sub2.id
  route_table_id = aws_route_table.public-rt.id
}
# create elastic ip for NAT gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
    Name = "${local.name}-nat-eip"
  }
}
# create NAT gateway so the private jenkins server can reach the internet
resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.pub_sub.id
  tags = {
    Name = "${local.name}-ngw"
  }
  depends_on = [aws_internet_gateway.igw]
}
# Create route table for private subnet
resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }
  tags = {
    Name = "${local.name}-pri-rt"
  }
}
resource "aws_route_table_association" "associate_private_subnet" {
  subnet_id      = aws_subnet.pri_sub.id
  route_table_id = aws_route_table.private-rt.id
}
# Create keypair resource
resource "tls_private_key" "keypair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "local_file" "private-key" {
  content         = tls_private_key.keypair.private_key_pem
  filename        = "${local.name}-key.pem"
  file_permission = "400"
}
resource "aws_key_pair" "public_key" {
  key_name   = "${local.name}-key"
  public_key = tls_private_key.keypair.public_key_openssh
}
# Data source to get the latest RedHat AMI
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

# Customer managed KMS key, CloudWatch monitoring and AWS Backup (shared modules)
module "kms" {
  source = "../module/kms"
  name   = local.name
  region = var.region
}

module "monitoring" {
  source      = "../module/monitoring"
  name        = local.name
  region      = var.region
  kms_key_arn = module.kms.key_arn
  vpc_id      = aws_vpc.vpc.id
  alert_email = var.alert_email
  instances = {
    jenkins = aws_instance.jenkins-server.id
  }
  load_balancers = {
    jenkins = aws_lb.jenkins.arn_suffix
  }
  target_groups = {
    jenkins = { lb_arn_suffix = aws_lb.jenkins.arn_suffix, tg_arn_suffix = aws_lb_target_group.jenkins.arn_suffix }
  }
  web_acls = {
    jenkins = module.waf.web_acl_name
  }
}

module "backup" {
  source        = "../module/backup"
  name          = local.name
  kms_key_arn   = module.kms.key_arn
  sns_topic_arn = module.monitoring.sns_topic_arn
}

resource "aws_instance" "jenkins-server" {
  ami                         = data.aws_ami.redhat.id
  instance_type               = "t3.medium"
  key_name                    = aws_key_pair.public_key.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.jenkins_security_group.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins_ssm_instance_profile.name
  subnet_id                   = aws_subnet.pri_sub.id
  depends_on                  = [aws_route_table_association.associate_private_subnet]
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = module.kms.key_arn
  }
  user_data = join("\n", [
    "#!/bin/bash",
    "AWS_REGION=${var.region}",
    "CW_CONFIG_PARAM=${module.monitoring.cw_config_param}",
    file("../module/common/bootstrap.sh"),
    file("./jenkins-user-data.sh"),
  ])
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name   = "${local.name}-jenkins-server"
    Backup = local.name
  }
}

# Create IAM role for Jenkins server
resource "aws_iam_role" "jenkins-ssm-jenkins-role" {
  name = "${local.name}-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Session Manager access (role based, no SSH)
resource "aws_iam_role_policy_attachment" "jenkins_ssm_managed_instance_core" {
  role       = aws_iam_role.jenkins-ssm-jenkins-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
# CloudWatch agent
resource "aws_iam_role_policy_attachment" "jenkins_cw_agent" {
  role       = aws_iam_role.jenkins-ssm-jenkins-role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
# Scoped deploy policy for the infrastructure pipeline (replaces AdministratorAccess)
resource "aws_iam_policy" "jenkins_deploy" {
  name        = "${local.name}-deploy-policy"
  description = "Least privilege permissions for Jenkins to run terraform for ${var.workload_name}"
  policy      = data.aws_iam_policy_document.jenkins_deploy.json
}
resource "aws_iam_role_policy_attachment" "jenkins_deploy" {
  role       = aws_iam_role.jenkins-ssm-jenkins-role.name
  policy_arn = aws_iam_policy.jenkins_deploy.arn
}
# CREATE INSTANCE PROFILE FOR JENKINS SERVER
resource "aws_iam_instance_profile" "jenkins_ssm_instance_profile" {
  name = "${local.name}-jenkins-profile"
  role = aws_iam_role.jenkins-ssm-jenkins-role.name
}

# Create jenkins security group
resource "aws_security_group" "jenkins_security_group" {
  name        = "${local.name}-jenkins-sg"
  description = "Allow Jenkins UI from the ALB only"
  vpc_id      = aws_vpc.vpc.id
  # only the jenkins ALB can reach the jenkins UI
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins-elb-security-group.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${local.name}-jenkins-sg"
  }
}

# Create ACM certificate with DNS validation
resource "aws_acm_certificate" "team-1-acm-cert" {
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name}-acm-cert"
  }
}

data "aws_route53_zone" "team-1-acp-zone" {
  name         = var.domain
  private_zone = false
}

# Fetch DNS Validation Records for ACM Certificate
resource "aws_route53_record" "acm_validation_record" {
  for_each = {
    for dvo in aws_acm_certificate.team-1-acm-cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  # Create DNS Validation Record for ACM Certificate
  zone_id         = data.aws_route53_zone.team-1-acp-zone.zone_id
  allow_overwrite = true
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  depends_on      = [aws_acm_certificate.team-1-acm-cert]
}

# Validate the ACM Certificate after DNS Record Creation
resource "aws_acm_certificate_validation" "team-1_cert_validation" {
  certificate_arn         = aws_acm_certificate.team-1-acm-cert.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation_record : record.fqdn]
  depends_on              = [aws_acm_certificate.team-1-acm-cert]
}

# Create Security group for the jenkins ALB
resource "aws_security_group" "jenkins-elb-security-group" {
  name        = "${local.name}-jenkins-elb-sg"
  description = "Allow HTTP and HTTPS"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    description = "HTTP (redirected to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${local.name}-jenkins-elb-sg"
  }
}

# Create Application Load Balancer for Jenkins (protected by WAF)
resource "aws_lb" "jenkins" {
  name                       = "${local.name}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.jenkins-elb-security-group.id]
  subnets                    = [aws_subnet.pub_sub.id, aws_subnet.pub_sub2.id]
  drop_invalid_header_fields = true
  tags = {
    Name = "${local.name}-alb"
  }
}

resource "aws_lb_target_group" "jenkins" {
  name     = "${local.name}-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    path                = "/login"
  }
  tags = {
    Name = "${local.name}-tg"
  }
}

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = aws_lb_target_group.jenkins.arn
  target_id        = aws_instance.jenkins-server.id
  port             = 8080
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.jenkins.arn
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
  load_balancer_arn = aws_lb.jenkins.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.team-1_cert_validation.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
}

# WAF in front of the Jenkins ALB (large bodies allowed for plugin/artifact uploads)
module "waf" {
  source                      = "../module/waf"
  name                        = local.name
  kms_key_arn                 = module.kms.key_arn
  rate_limit                  = 10000
  common_rule_count_overrides = ["SizeRestrictions_BODY", "CrossSiteScripting_BODY"] # XML/HTML in Jenkins config forms
  sqli_rule_count_overrides   = ["SQLi_BODY"]
  # SonarQube posts quality gate results to Jenkins; its JSON body trips the SSRF rule
  rule_path_exemptions = {
    ssrf-body = { rule = "EC2MetaDataSSRF_BODY", label = "EC2MetaDataSSRF_Body", paths = ["/sonarqube-webhook/"] }
  }
  alb_arns = {
    jenkins = aws_lb.jenkins.arn
  }
}

# Create Route 53 record for jenkins server
resource "aws_route53_record" "jenkins-record" {
  zone_id = data.aws_route53_zone.team-1-acp-zone.id
  name    = "jenkins.${var.domain}"
  type    = "A"
  alias {
    name                   = aws_lb.jenkins.dns_name
    zone_id                = aws_lb.jenkins.zone_id
    evaluate_target_health = true
  }
}
