variable "proxmox_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://62.210.88.216:8006"
}

variable "proxmox_token_id" {
  description = "Proxmox API token ID (e.g. root@pam!terraform)"
  type        = string
}

variable "proxmox_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "jan26-group6-eshopOnContainers"
}

variable "ssh_public_key" {
  description = "SSH public key added to all VMs"
  type        = string
}

variable "vm_storage" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "vmdata"
}

variable "network_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for Proxmox host access"
  type        = string
  default     = "~/.ssh/id_ed25519"
}
