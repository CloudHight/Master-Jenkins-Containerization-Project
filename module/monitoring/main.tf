data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Alerting: encrypted SNS topic (+ optional e-mail subscription)
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = var.kms_key_arn
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountOwner"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = ["SNS:Publish", "SNS:Subscribe", "SNS:GetTopicAttributes", "SNS:SetTopicAttributes", "SNS:ListSubscriptionsByTopic"]
        Resource  = aws_sns_topic.alerts.arn
      },
      {
        Sid       = "AlarmAndBackupPublish"
        Effect    = "Allow"
        Principal = { Service = ["cloudwatch.amazonaws.com", "backup.amazonaws.com"] }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# CloudWatch agent: log group + config stored in SSM (read by every server)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ec2" {
  name              = "/${var.name}/ec2"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

locals {
  log_files = ["/var/log/messages", "/var/log/secure", "/var/log/syslog", "/var/log/auth.log", "/var/log/cloud-init-output.log"]
}

# Name must start with AmazonCloudWatch- so CloudWatchAgentServerPolicy can read it
resource "aws_ssm_parameter" "cw_agent_config" {
  name = "AmazonCloudWatch-${var.name}"
  type = "String"
  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "root"
    }
    metrics = {
      namespace = "CWAgent"
      append_dimensions = {
        InstanceId           = "$${aws:InstanceId}"
        AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
      }
      aggregation_dimensions = [["InstanceId"], ["AutoScalingGroupName"]]
      metrics_collected = {
        mem = { measurement = ["mem_used_percent"] }
        disk = {
          measurement = ["used_percent"]
          resources   = ["/"]
          drop_device = true
        }
      }
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [for f in local.log_files : {
            file_path       = f
            log_group_name  = aws_cloudwatch_log_group.ec2.name
            log_stream_name = "{instance_id}${f}"
          }]
        }
      }
    }
  })
}

# ---------------------------------------------------------------------------
# VPC flow logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/${var.name}/vpc-flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.name}-flowlogs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.name}-flowlogs-write"
  role = aws_iam_role.flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id          = var.vpc_id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn    = aws_iam_role.flow_logs.arn
}

# ---------------------------------------------------------------------------
# Alarms
# ---------------------------------------------------------------------------
locals {
  actions = [aws_sns_topic.alerts.arn]
}

# EC2 instances
resource "aws_cloudwatch_metric_alarm" "instance_cpu" {
  for_each            = var.instances
  alarm_name          = "${var.name}-${each.key}-cpu-high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = each.value }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "instance_status" {
  for_each            = var.instances
  alarm_name          = "${var.name}-${each.key}-status-check-failed"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = each.value }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "instance_memory" {
  for_each            = var.instances
  alarm_name          = "${var.name}-${each.key}-memory-high"
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  dimensions          = { InstanceId = each.value }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "instance_disk" {
  for_each            = var.instances
  alarm_name          = "${var.name}-${each.key}-disk-high"
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  dimensions          = { InstanceId = each.value }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# Auto Scaling groups
resource "aws_cloudwatch_metric_alarm" "asg_cpu" {
  for_each            = var.asgs
  alarm_name          = "${var.name}-${each.key}-asg-cpu-high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { AutoScalingGroupName = each.value }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "asg_memory" {
  for_each            = var.asgs
  alarm_name          = "${var.name}-${each.key}-asg-memory-high"
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  dimensions          = { AutoScalingGroupName = each.value }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# Application Load Balancers
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  for_each            = var.load_balancers
  alarm_name          = "${var.name}-${each.key}-alb-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = { LoadBalancer = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  for_each            = var.load_balancers
  alarm_name          = "${var.name}-${each.key}-alb-latency-high"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = each.value }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 2
  threshold           = 2
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "target_unhealthy" {
  for_each            = var.target_groups
  alarm_name          = "${var.name}-${each.key}-unhealthy-targets"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = { LoadBalancer = each.value.lb_arn_suffix, TargetGroup = each.value.tg_arn_suffix }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  for_each            = var.target_groups
  alarm_name          = "${var.name}-${each.key}-target-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = each.value.lb_arn_suffix, TargetGroup = each.value.tg_arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# WAF
resource "aws_cloudwatch_metric_alarm" "waf_blocked" {
  for_each            = var.web_acls
  alarm_name          = "${var.name}-${each.key}-waf-blocked-spike"
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  dimensions          = { WebACL = each.value, Region = var.region, Rule = "ALL" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.waf_blocked_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
}

# RDS
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  for_each            = var.rds_instances
  alarm_name          = "${var.name}-${each.key}-rds-cpu-high"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = each.value }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  for_each            = var.rds_instances
  alarm_name          = "${var.name}-${each.key}-rds-storage-low"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = each.value }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2147483648 # 2 GiB
  comparison_operator = "LessThanThreshold"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------
locals {
  lb_widgets = length(var.load_balancers) == 0 ? [] : [
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title   = "ALB requests"
        region  = var.region
        stat    = "Sum"
        period  = 300
        metrics = [for k, v in var.load_balancers : ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", v, { label = k }]]
      }
    },
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title   = "ALB 5xx"
        region  = var.region
        stat    = "Sum"
        period  = 300
        metrics = [for k, v in var.load_balancers : ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", v, { label = k }]]
      }
    }
  ]
  instance_widgets = length(var.instances) == 0 ? [] : [
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title   = "Instance CPU %"
        region  = var.region
        stat    = "Average"
        period  = 300
        metrics = [for k, v in var.instances : ["AWS/EC2", "CPUUtilization", "InstanceId", v, { label = k }]]
      }
    },
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title   = "Instance memory %"
        region  = var.region
        stat    = "Average"
        period  = 300
        metrics = [for k, v in var.instances : ["CWAgent", "mem_used_percent", "InstanceId", v, { label = k }]]
      }
    }
  ]
  asg_widgets = length(var.asgs) == 0 ? [] : [
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title   = "ASG CPU %"
        region  = var.region
        stat    = "Average"
        period  = 300
        metrics = [for k, v in var.asgs : ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", v, { label = k }]]
      }
    }
  ]
  waf_widgets = length(var.web_acls) == 0 ? [] : [
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title   = "WAF blocked requests"
        region  = var.region
        stat    = "Sum"
        period  = 300
        metrics = [for k, v in var.web_acls : ["AWS/WAFV2", "BlockedRequests", "WebACL", v, "Region", var.region, "Rule", "ALL", { label = k }]]
      }
    }
  ]
  rds_widgets = length(var.rds_instances) == 0 ? [] : [
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title   = "RDS CPU %"
        region  = var.region
        stat    = "Average"
        period  = 300
        metrics = [for k, v in var.rds_instances : ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", v, { label = k }]]
      }
    }
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name}-overview"
  dashboard_body = jsonencode({
    widgets = concat(local.lb_widgets, local.instance_widgets, local.asg_widgets, local.waf_widgets, local.rds_widgets)
  })
}
