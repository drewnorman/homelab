# Consolidated NixOS VM target.
#
# lab-core owns the router DNS IP and runs the consolidated service stack.

resource "proxmox_virtual_environment_vm" "core" {
  count = var.enable_core_vm ? 1 : 0

  vm_id       = local.core_vm.vm_id
  name        = local.core_vm.hostname
  node_name   = var.proxmox_node_name
  description = "Consolidated NixOS homelab VM — managed by OpenTofu and deploy-rs"
  tags        = ["core", "homelab", "nixos", "vm"]

  started = true
  on_boot = true

  boot_order = ["virtio0"]

  agent {
    enabled = true
  }

  clone {
    vm_id        = var.core_vm_template_vm_id
    datastore_id = var.core_vm_storage
    full         = true
  }

  cpu {
    cores = var.core_vm_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.core_vm_memory_mb
    floating  = var.core_vm_memory_mb
  }

  disk {
    datastore_id = var.core_vm_storage
    interface    = "virtio0"
    size         = var.core_vm_disk_gb
    discard      = "on"
  }

  initialization {
    datastore_id = var.core_vm_storage

    dns {
      domain  = var.search_domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${local.core_vm.ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_account {
      username = "root"
      keys     = [trimspace(var.ssh_public_key)]
    }
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      # The external media SSD is attached by terraform_data.core_media_disk
      # because Proxmox only allows arbitrary host paths through root.
      disk,
      initialization[0].user_account,
    ]
  }
}

resource "terraform_data" "core_media_disk" {
  count = var.enable_core_vm ? 1 : 0

  triggers_replace = [
    tostring(local.core_vm.vm_id),
    var.proxmox_ssh_host,
    var.core_vm_media_disk_path,
  ]

  provisioner "local-exec" {
    command = "ssh root@${var.proxmox_ssh_host} 'qm set ${local.core_vm.vm_id} --scsi1 ${var.core_vm_media_disk_path},backup=0,discard=on,ssd=1'"
  }

  depends_on = [proxmox_virtual_environment_vm.core]
}
