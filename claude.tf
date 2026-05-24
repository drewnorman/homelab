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

# Domain mapping: serve claude.lab.adre.me from Cloud Run.
# Domain ownership of lab.adre.me is verified in dns.tf via google_site_verification_owner.

# Step 1 — map the custom domain to the Cloud Run service.
# Returns the DNS records (CNAME target) Cloud Run needs to route traffic.
resource "google_cloud_run_domain_mapping" "claude_troubleshooter" {
  count    = var.enable_claude_troubleshooter && var.enable_cloudflare_dns ? 1 : 0
  location = var.gcp_region
  name     = "claude.lab.${var.cloudflare_zone_name}"

  metadata {
    namespace = var.gcp_project
  }

  spec {
    route_name = google_cloud_run_v2_service.claude_troubleshooter[0].name
  }

  depends_on = [google_site_verification_owner.lab_domain]
}

# Step 2 — point claude.lab.adre.me at the CNAME Cloud Run provides via the mapping.
# When enable_cloudflare_dns is false the mapping is skipped and the service is
# reachable only via the claude_troubleshooter_uri output.
resource "cloudflare_dns_record" "claude_troubleshooter" {
  count   = var.enable_claude_troubleshooter && var.enable_cloudflare_dns ? 1 : 0
  zone_id = local.cloudflare_managed_zone_id
  name    = "claude.lab.${var.cloudflare_zone_name}"
  type    = "CNAME"
  content = one([
    for r in google_cloud_run_domain_mapping.claude_troubleshooter[0].status[0].resource_records
    : r.rrdata if r.type == "CNAME"
  ])
  ttl     = 3600
  proxied = false
  comment = "Managed by OpenTofu"
}
