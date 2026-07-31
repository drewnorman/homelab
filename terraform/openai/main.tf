locals {
  project_name         = "homelab-ai-production"
  service_account_name = "homelab-ai-production-open-webui"
  model_ids = [
    "gpt-5.6-luna",
    "gpt-5.6-terra",
    "gpt-5.6-sol",
  ]
  spend_alerts = {
    warning = 1000
    urgent  = 1600
  }
}

resource "openai_project" "production" {
  name = local.project_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "openai_project_service_account" "open_webui" {
  project_id = openai_project.production.project_id
  name       = local.service_account_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "openai_project_role" "responses_writer" {
  project_id  = openai_project.production.project_id
  role_name   = "${local.project_name}-responses-writer"
  description = "Allows the Open WebUI workload to create Responses only."
  permissions = ["api.responses.write"]
}

resource "openai_group" "open_webui" {
  name = local.service_account_name
}

resource "openai_group_user" "open_webui_service_account" {
  group_id = openai_group.open_webui.group_id
  user_id  = openai_project_service_account.open_webui.service_account_id
}

resource "openai_project_group_role" "responses_writer" {
  project_id = openai_project.production.project_id
  group_id   = openai_group.open_webui.group_id
  role_id    = openai_project_role.responses_writer.role_id
}

resource "openai_project_model_permissions" "production" {
  project_id = openai_project.production.project_id
  mode       = "allow_list"
  model_ids  = local.model_ids
}

resource "openai_project_data_retention" "production" {
  project_id = openai_project.production.project_id
  type       = "organization_default"
}

resource "openai_project_spend_alert" "monthly_email" {
  for_each = local.spend_alerts

  project_id                      = openai_project.production.project_id
  threshold_amount                = each.value
  currency                        = "USD"
  interval                        = "month"
  notification_channel_type       = "email"
  notification_channel_recipients = ["drewnorman739@gmail.com"]
  notification_channel_subject_prefix = format(
    "[homelab-ai-production %s]",
    each.key,
  )
}

# This must remain disabled until every applicable organization hosted-tool
# policy is manually changed from "all projects" to "selected projects".
resource "openai_project_hosted_tool_permissions" "production" {
  count = var.enable_hosted_tool_permissions ? 1 : 0

  project_id               = openai_project.production.project_id
  web_search_enabled       = true
  file_search_enabled      = false
  image_generation_enabled = false
  mcp_enabled              = false
  code_interpreter_enabled = false
}

data "openai_project_rate_limits" "available" {
  project_id = openai_project.production.project_id
}

resource "openai_project_rate_limit" "conservative" {
  for_each = var.model_rate_limit_ids

  project_id                = openai_project.production.project_id
  rate_limit_id             = each.value
  max_requests_per_1_minute = 10
  max_tokens_per_1_minute   = 100000
}
