provider "google" {
  project               = "personal-drewnorman739"
  billing_project       = "personal-drewnorman739"
  user_project_override = true
}

resource "google_project_service" "api_keys" {
  project            = "personal-drewnorman739"
  service            = "apikeys.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "youtube" {
  project            = "personal-drewnorman739"
  service            = "youtube.googleapis.com"
  disable_on_destroy = false
}

resource "google_apikeys_key" "cat_tv" {
  project      = "personal-drewnorman739"
  name         = "homelab-cat-tv"
  display_name = "Homelab Cat TV"

  restrictions {
    api_targets {
      service = "youtube.googleapis.com"
    }
  }

  depends_on = [google_project_service.api_keys, google_project_service.youtube]

  lifecycle {
    prevent_destroy = true
  }
}
