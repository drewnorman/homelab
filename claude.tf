locals {
  claude_troubleshooter_name = "claude-troubleshooter"
}

resource "google_project_service" "run" {
  count   = var.enable_claude_troubleshooter ? 1 : 0
  project = var.gcp_project
  service = "run.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  count   = var.enable_claude_troubleshooter ? 1 : 0
  project = var.gcp_project
  service = "secretmanager.googleapis.com"

  disable_on_destroy = false
}

resource "google_service_account" "claude_troubleshooter" {
  count        = var.enable_claude_troubleshooter ? 1 : 0
  project      = var.gcp_project
  account_id   = local.claude_troubleshooter_name
  display_name = "Claude Troubleshooter"
}

resource "google_secret_manager_secret" "anthropic_api_key" {
  count     = var.enable_claude_troubleshooter ? 1 : 0
  project   = var.gcp_project
  secret_id = "claude-troubleshooter-anthropic-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "anthropic_api_key" {
  count       = var.enable_claude_troubleshooter ? 1 : 0
  secret      = google_secret_manager_secret.anthropic_api_key[0].id
  secret_data = var.anthropic_api_key
}

resource "google_secret_manager_secret_iam_member" "claude_troubleshooter" {
  count     = var.enable_claude_troubleshooter ? 1 : 0
  project   = var.gcp_project
  secret_id = google_secret_manager_secret.anthropic_api_key[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.claude_troubleshooter[0].email}"
}

resource "google_cloud_run_v2_service" "claude_troubleshooter" {
  count    = var.enable_claude_troubleshooter ? 1 : 0
  project  = var.gcp_project
  name     = local.claude_troubleshooter_name
  location = var.gcp_region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.claude_troubleshooter[0].email

    containers {
      image = var.claude_troubleshooter_image

      env {
        name = "ANTHROPIC_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.anthropic_api_key[0].secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.run,
    google_secret_manager_secret_iam_member.claude_troubleshooter,
  ]
}

# Allow unauthenticated access so the web UI is reachable in a browser.
# The application is responsible for its own authentication.
resource "google_cloud_run_v2_service_iam_member" "claude_troubleshooter_public_invoker" {
  count    = var.enable_claude_troubleshooter ? 1 : 0
  project  = var.gcp_project
  location = var.gcp_region
  name     = google_cloud_run_v2_service.claude_troubleshooter[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# DNS: point claude.lab.adre.me at the Cloud Run service.
# Within the homelab, *.lab.adre.me resolves to lab-edge via AdGuard; Caddy on lab-edge
# must be configured with claude.lab.adre.me as an edge_extra_service to proxy to this URI.
# Externally, this CNAME resolves to the Cloud Run host, but Cloud Run will only serve
# claude.lab.adre.me after domain verification and a google_cloud_run_domain_mapping is added.
# Until then, use the claude_troubleshooter_uri output for direct external access.
resource "cloudflare_dns_record" "claude_troubleshooter" {
  count   = var.enable_claude_troubleshooter && var.enable_cloudflare_dns ? 1 : 0
  zone_id = local.cloudflare_managed_zone_id
  name    = "claude.lab.${var.cloudflare_zone_name}"
  type    = "CNAME"
  content = trimprefix(google_cloud_run_v2_service.claude_troubleshooter[0].uri, "https://")
  ttl     = 3600
  proxied = false
  comment = "Managed by OpenTofu"
}
