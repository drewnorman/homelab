output "project_id" {
  description = "OpenAI project ID."
  value       = openai_project.production.project_id
}

output "service_account_id" {
  description = "Open WebUI service-account ID."
  value       = openai_project_service_account.open_webui.service_account_id
}

output "group_id" {
  description = "Open WebUI workload group ID."
  value       = openai_group.open_webui.group_id
}

output "role_id" {
  description = "Responses-writer project role ID."
  value       = openai_project_role.responses_writer.role_id
}

output "available_model_rate_limits" {
  description = "OpenAI-created rate-limit records for the three allowed models. Copy their IDs into ignored terraform.tfvars."
  value = [
    for limit in data.openai_project_rate_limits.available.rate_limits : {
      id                       = limit.id
      model                    = limit.model
      requests_per_minute      = limit.max_requests_per_1_minute
      tokens_per_minute        = limit.max_tokens_per_1_minute
      requests_per_day         = limit.max_requests_per_1_day
      batch_1_day_input_tokens = limit.batch_1_day_max_input_tokens
    }
    if contains(local.model_ids, limit.model)
  ]
}
