resource "proxmox_download_file" "nixos_lxc_template" {
  count = var.enable_nix_host && var.manage_nix_lxc_template ? 1 : 0

  node_name           = var.proxmox_node_name
  datastore_id        = var.nix_lxc_template_datastore_id
  content_type        = "vztmpl"
  file_name           = var.nix_lxc_template_file_name
  url                 = var.nix_lxc_template_url
  overwrite           = false
  overwrite_unmanaged = false
  upload_timeout      = var.nix_lxc_template_download_timeout_seconds
}
