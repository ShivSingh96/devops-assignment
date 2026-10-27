output "instance_ids" {
  description = "Instance name => instance ID"
  value = merge(
    { for k, i in aws_instance.protected : k => i.id },
    { for k, i in aws_instance.normal : k => i.id },
  )
}

output "instance_private_ips" {
  description = "Instance name => private IP"
  value = merge(
    { for k, i in aws_instance.protected : k => i.private_ip },
    { for k, i in aws_instance.normal : k => i.private_ip },
  )
}

output "private_keys" {
  description = "Instance name => private key (PEM). Retrieve with: terraform output -json private_keys"
  sensitive   = true
  value       = { for k, t in tls_private_key.this : k => t.private_key_openssh }
}
