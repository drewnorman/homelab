variable "enable_hosted_tool_permissions" {
  description = "Manage project hosted-tool permissions after the organization policies have been changed from all projects to selected projects."
  type        = bool
  default     = false
}

variable "model_rate_limit_ids" {
  description = "OpenAI-created rate-limit record IDs keyed by model ID. Discover these after the first apply and set them in ignored terraform.tfvars."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for model, id in var.model_rate_limit_ids :
      contains(["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol"], model) &&
      trimspace(id) != ""
    ])
    error_message = "model_rate_limit_ids may contain only gpt-5.6-luna, gpt-5.6-terra, and gpt-5.6-sol with non-empty record IDs."
  }

  validation {
    condition     = length(var.model_rate_limit_ids) == 0 || length(var.model_rate_limit_ids) == 3
    error_message = "Configure either no model rate limits (first stage) or explicit record IDs for all three models."
  }
}
