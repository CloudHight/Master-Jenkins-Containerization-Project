# Least privilege deploy policy for the Jenkins infrastructure pipeline.
# Jenkins runs terraform for the "${var.workload_name}" stack, so it gets only the services that
# stack uses, in one region, and can only manage IAM roles / secrets / keys named for that workload.
locals {
  account_id = data.aws_caller_identity.current.account_id
  workload   = var.workload_name
}

data "aws_iam_policy_document" "jenkins_deploy" {
  # Regional infrastructure services used by the stack
  statement {
    sid    = "RegionalInfrastructure"
    effect = "Allow"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
      "wafv2:*",
      "rds:*",
      "backup:*",
      "backup-storage:MountCapsule",
      "cloudwatch:*",
      "logs:*",
      "sns:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # KMS: create keys, and manage only keys tagged Name = <workload>-*
  statement {
    sid    = "KmsCreate"
    effect = "Allow"
    # DescribeKey (metadata only): RDS checks the AWS managed aws/secretsmanager key, which has no workload tag
    actions   = ["kms:CreateKey", "kms:ListKeys", "kms:ListAliases", "kms:DescribeKey"]
    resources = ["*"]
  }
  statement {
    sid       = "KmsTagOnCreate"
    effect    = "Allow"
    actions   = ["kms:TagResource"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/Name"
      values   = ["${local.workload}-*"]
    }
  }
  statement {
    sid       = "KmsManageWorkloadKeys"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["arn:aws:kms:${var.region}:${local.account_id}:key/*"]
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/Name"
      values   = ["${local.workload}-*"]
    }
  }
  statement {
    sid       = "KmsWorkloadAliases"
    effect    = "Allow"
    actions   = ["kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias"]
    resources = ["arn:aws:kms:${var.region}:${local.account_id}:alias/${local.workload}-*"]
  }

  # Secrets Manager: only the workload's secrets (+ the RDS managed master secret)
  statement {
    sid       = "WorkloadSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:*"]
    resources = ["arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:${local.workload}/*"]
  }
  statement {
    sid       = "RdsManagedSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:CreateSecret", "secretsmanager:TagResource", "secretsmanager:DescribeSecret"]
    resources = ["arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:rds!*"]
  }
  statement {
    sid       = "SecretsRead"
    effect    = "Allow"
    actions   = ["secretsmanager:ListSecrets", "secretsmanager:GetRandomPassword"]
    resources = ["*"]
  }

  # SSM parameter holding the CloudWatch agent config
  statement {
    sid       = "CloudWatchAgentConfig"
    effect    = "Allow"
    actions   = ["ssm:PutParameter", "ssm:GetParameter", "ssm:GetParameters", "ssm:DeleteParameter", "ssm:AddTagsToResource", "ssm:ListTagsForResource"]
    resources = ["arn:aws:ssm:${var.region}:${local.account_id}:parameter/AmazonCloudWatch-${local.workload}"]
  }
  statement {
    sid       = "SsmDescribe"
    effect    = "Allow"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }

  # SSM Run Command: deploy pipelines run Ansible on the workload's Ansible server only
  statement {
    sid       = "RunShellScriptDocument"
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:${var.region}::document/AWS-RunShellScript"]
  }
  statement {
    sid       = "RunCommandOnAnsibleServer"
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${var.region}:${local.account_id}:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Name"
      values   = ["${local.workload}-ansible-server"]
    }
  }
  statement {
    sid       = "RunCommandResults"
    effect    = "Allow"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }

  # IAM: only roles / instance profiles named <workload>-*
  statement {
    sid    = "WorkloadRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole", "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${local.workload}-*",
      "arn:aws:iam::${local.account_id}:instance-profile/${local.workload}-*",
    ]
  }
  # Only these AWS managed policies may be attached (prevents attaching AdministratorAccess)
  statement {
    sid       = "AttachApprovedManagedPolicies"
    effect    = "Allow"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.workload}-*"]
    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values = [
        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
        "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
        "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
      ]
    }
  }
  statement {
    sid       = "PassWorkloadRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.workload}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com", "vpc-flow-logs.amazonaws.com", "backup.amazonaws.com"]
    }
  }
  statement {
    sid       = "ServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com", "autoscaling.amazonaws.com", "rds.amazonaws.com", "wafv2.amazonaws.com"]
    }
  }
  statement {
    sid       = "IamRead"
    effect    = "Allow"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions"]
    resources = ["*"]
  }

  # DNS records in the project hosted zone, read-only ACM
  statement {
    sid       = "Route53Zone"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets", "route53:GetHostedZone", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
    resources = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.team-1-acp-zone.zone_id}"]
  }
  statement {
    sid       = "Route53Read"
    effect    = "Allow"
    actions   = ["route53:ListHostedZones", "route53:ListHostedZonesByName", "route53:GetChange"]
    resources = ["*"]
  }
  statement {
    sid       = "AcmRead"
    effect    = "Allow"
    actions   = ["acm:DescribeCertificate", "acm:ListCertificates", "acm:GetCertificate", "acm:ListTagsForCertificate"]
    resources = ["*"]
  }

  # S3: only buckets named <workload>-* (ansible scripts bucket)
  statement {
    sid       = "WorkloadBuckets"
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${local.workload}-*", "arn:aws:s3:::${local.workload}-*/*"]
  }

  statement {
    sid       = "Identity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}
