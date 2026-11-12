output "cat_tv_api_key" {
  description = "YouTube Data API key for the Home Assistant Cat TV discovery sensor. Store it only in SOPS."
  value       = google_apikeys_key.cat_tv.key_string
  sensitive   = true
}
