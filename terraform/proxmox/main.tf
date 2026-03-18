# ──────────────────────────────────────────────
# Download Ubuntu 22.04 cloud image to Proxmox
# ──────────────────────────────────────────────
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  node_name    = var.proxmox_node
  content_type = "iso"
  datastore_id = "local"

  file_name          = "ubuntu-22.04-cloudimg-amd64.img"
  url                = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  checksum_algorithm = "sha256"
  checksum           = "b9af0301d4fcc94ce886ce6b624506078cd84c8a29b6ff54689c7a70fb62619e"
}

# ──────────────────────────────────────────────
# VM definitions
# ──────────────────────────────────────────────
locals {
  vms = {
    gitlab-ce = {
      vm_id       = 101
      cores       = 4
      memory      = 16384
      disk_size   = 100
      description = "GitLab CE + Container Registry"
    }
    gitlab-runner = {
      vm_id       = 102
      cores       = 4
      memory      = 8192
      disk_size   = 60
      description = "GitLab CI Runner (Docker executor)"
    }
    k3s-dev = {
      vm_id       = 103
      cores       = 4
      memory      = 8192
      disk_size   = 50
      description = "k3s node — dev environment"
    }
    k3s-staging = {
      vm_id       = 104
      cores       = 4
      memory      = 8192
      disk_size   = 50
      description = "k3s node — staging environment"
    }
    k3s-prod = {
      vm_id       = 105
      cores       = 4
      memory      = 8192
      disk_size   = 50
      description = "k3s node — production environment"
    }
  }
}

# ──────────────────────────────────────────────
# VMs (one per environment + GitLab + Runner)
# ──────────────────────────────────────────────
resource "proxmox_virtual_environment_vm" "vms" {
  for_each = local.vms

  name        = each.key
  description = each.value.description
  node_name   = var.proxmox_node
  vm_id       = each.value.vm_id

  on_boot = true

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.vm_storage
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    size         = each.value.disk_size
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  boot_order = ["virtio0"]

  agent {
    enabled = true
  }

  initialization {
    datastore_id = "local"

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }

    dns {
      servers = ["8.8.8.8", "8.8.4.4"]
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }
}
