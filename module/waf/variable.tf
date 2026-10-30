variable "name" {}
variable "kms_key_arn" {}

variable "alb_arns" {
  type        = map(string)
  description = "ALBs to protect, keyed by a static name"
}

variable "rate_limit" {
  type        = number
  default     = 2000
  description = "Max requests per IP in a 5 minute window"
}

variable "common_rule_count_overrides" {
  type        = list(string)
  default     = []
  description = "AWSManagedRulesCommonRuleSet rules to run in count mode"
}

variable "rule_path_exemptions" {
  type = map(object({
    rule     = string                     # rule name in the managed rule group
    label    = string                     # label that rule adds (<namespace>:<label>)
    paths    = list(string)               # URI path prefixes where the rule is not enforced
    rule_set = optional(string, "common") # "common" (CommonRuleSet) or "sqli" (SQLiRuleSet)
  }))
  default     = {}
  description = "Managed rules enforced everywhere except some paths"
  validation {
    condition     = alltrue([for e in var.rule_path_exemptions : contains(["common", "sqli"], e.rule_set)])
    error_message = "rule_set must be \"common\" or \"sqli\"."
  }
}

variable "sqli_rule_count_overrides" {
  type        = list(string)
  default     = []
  description = "AWSManagedRulesSQLiRuleSet rules to run in count mode"
}

variable "log_retention_days" {
  default = 90
}
