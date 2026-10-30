output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "cw_config_param" {
  value = aws_ssm_parameter.cw_agent_config.name
}
