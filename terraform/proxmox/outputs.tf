output "vm_ids" {
  description = "VM IDs for all created VMs"
  value       = { for k, v in proxmox_virtual_environment_vm.vms : k => v.vm_id }
}

output "vm_ipv4_addresses" {
  description = "IPv4 addresses assigned to each VM (requires qemu-guest-agent to be running)"
  value       = { for k, v in proxmox_virtual_environment_vm.vms : k => v.ipv4_addresses }
}
