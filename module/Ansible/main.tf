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
#Creating ansible security group
resource "aws_security_group" "ansible-security-group" {
  name        = "${var.name}ansible-sg"
  description = "Allow ssh"
  vpc_id      = var.vpc

  ingress {
    description     = "sshport"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_key]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.name}-ansible-sg"
  }
}

# Create Ansible Server
resource "aws_instance" "ansible-server" {
  ami                    = data.aws_ami.redhat.id #rehat 
  instance_type          = "t3.small"             # t2.micro (1 GB) ran out of memory during dnf and never finished user_data
  iam_instance_profile   = aws_iam_instance_profile.IAM-ansible-profile.name
  vpc_security_group_ids = [aws_security_group.ansible-security-group.id]
  key_name               = var.keypair
  subnet_id              = var.subnet_id
  user_data              = local.ansible_userdata
  # user_data only runs on first boot, so rebuild the server when it changes (it keeps no state)
  user_data_replace_on_change = true
  depends_on                  = [aws_s3_object.ansible-scripts]
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
    Name   = "${var.name}-ansible-server"
    Backup = var.name
  }
}

# Create IAM role for ansible
resource "aws_iam_role" "ansible-IAM-role" {
  name = "${var.name}-ansible-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}
# Least privilege: discover ASG instances, read its scripts and its SSH key only
resource "aws_iam_role_policy" "ansible-least-privilege" {
  name = "${var.name}-ansible-policy"
  role = aws_iam_role.ansible-IAM-role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DiscoverInstances"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Sid      = "ReadAnsibleScripts"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.ansible-scripts.arn}/ansible-script/*"
      },
      {
        Sid      = "ReadSshKey"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.ssh_key_secret_arn
      },
      {
        Sid      = "DecryptSecrets"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = var.kms_key_arn
      }
    ]
  })
}
# SSM (Session Manager) access
resource "aws_iam_role_policy_attachment" "IAM-ssm-policy" {
  role       = aws_iam_role.ansible-IAM-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
# CloudWatch agent
resource "aws_iam_role_policy_attachment" "IAM-cw-agent-policy" {
  role       = aws_iam_role.ansible-IAM-role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
# Create IAM instance profile for ansible
resource "aws_iam_instance_profile" "IAM-ansible-profile" {
  name = "${var.name}-ansible-profile"
  role = aws_iam_role.ansible-IAM-role.name
}
data "aws_caller_identity" "current" {}

# Private, KMS-encrypted bucket holding the scripts the ansible server pulls at boot
resource "aws_s3_bucket" "ansible-scripts" {
  bucket        = "${var.name}-ansible-scripts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags = {
    Name = "${var.name}-ansible-scripts"
  }
}
resource "aws_s3_bucket_public_access_block" "ansible-scripts" {
  bucket                  = aws_s3_bucket.ansible-scripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "ansible-scripts" {
  bucket = aws_s3_bucket.ansible-scripts.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "ansible-scripts" {
  bucket = aws_s3_bucket.ansible-scripts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}
# Upload the ansible scripts
resource "aws_s3_object" "ansible-scripts" {
  for_each   = fileset("${path.module}/scripts", "*")
  bucket     = aws_s3_bucket.ansible-scripts.id
  key        = "ansible-script/${each.value}"
  source     = "${path.module}/scripts/${each.value}"
  etag       = filemd5("${path.module}/scripts/${each.value}")
  depends_on = [aws_s3_bucket_server_side_encryption_configuration.ansible-scripts]
}
