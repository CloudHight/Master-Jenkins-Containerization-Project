data "aws_caller_identity" "current" {}

# Customer managed key for EBS, RDS, Secrets Manager, CloudWatch Logs, SNS and AWS Backup
resource "aws_kms_key" "cmk" {
  description             = "${var.name} customer managed key"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.cmk.json

  tags = {
    Name = "${var.name}-cmk"
  }
}

resource "aws_kms_alias" "cmk" {
  name          = "alias/${var.name}-cmk"
  target_key_id = aws_kms_key.cmk.key_id
}

data "aws_iam_policy_document" "cmk" {
  # Account admins manage the key; access for workloads is granted through IAM policies
  statement {
    sid       = "EnableIAMPolicies"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # CloudWatch Logs encrypts log groups in this account
  statement {
    sid       = "AllowCloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  # CloudWatch alarms and AWS Backup publish to the encrypted SNS alert topic
  statement {
    sid       = "AllowAlertPublishers"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "backup.amazonaws.com"]
    }
  }
}
