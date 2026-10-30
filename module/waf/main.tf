# Regional WAF in front of the ALBs: AWS managed rules + per-IP rate limiting
locals {
  # Label namespace each managed rule group adds to matching requests
  label_namespace = {
    common = "core-rule-set"
    sqli   = "sql-database"
  }
}

resource "aws_wafv2_web_acl" "this" {
  name  = "${var.name}-web-acl"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 0
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Rules switched to count-only (e.g. large uploads to Nexus/SonarQube/Jenkins)
        dynamic "rule_action_override" {
          for_each = toset(concat(var.common_rule_count_overrides, [for e in var.rule_path_exemptions : e.rule if e.rule_set == "common"]))
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"

        # Rules switched to count-only (e.g. Jenkins login/config forms trip SQLi_BODY)
        dynamic "rule_action_override" {
          for_each = toset(concat(var.sqli_rule_count_overrides, [for e in var.rule_path_exemptions : e.rule if e.rule_set == "sqli"]))
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-sqli"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 4
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # Re-block a count-only managed rule everywhere except some paths (matched on the rule's label,
  # so it must run after the rule groups). e.g. SonarQube's webhook body trips EC2MetaDataSSRF_BODY.
  dynamic "rule" {
    for_each = var.rule_path_exemptions
    content {
      name     = "${rule.key}-except-path"
      priority = 10 + index(keys(var.rule_path_exemptions), rule.key)
      action {
        block {}
      }
      statement {
        and_statement {
          statement {
            label_match_statement {
              scope = "LABEL"
              key   = "awswaf:managed:aws:${local.label_namespace[rule.value.rule_set]}:${rule.value.label}"
            }
          }
          statement {
            not_statement {
              statement {
                regex_match_statement {
                  regex_string = "^(${join("|", rule.value.paths)})"
                  field_to_match {
                    uri_path {}
                  }
                  text_transformation {
                    priority = 0
                    type     = "NONE"
                  }
                }
              }
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-${rule.key}-except-path"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.name}-web-acl"
  }
}

# WAF logs (log group name must start with aws-waf-logs-)
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.this.arn
}

# Attach the web ACL to each ALB
resource "aws_wafv2_web_acl_association" "this" {
  for_each     = var.alb_arns
  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
