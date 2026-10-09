output "api_endpoint" {
  description = "HA Kubernetes API (NLB)"
  value       = "https://${aws_lb.this.dns_name}:6443"
}

output "nlb_dns" {
  value = aws_lb.this.dns_name
}

output "app_test_command" {
  value = "curl -H 'Host: foo.bar.com' http://${aws_lb.this.dns_name}/demo/"
}

output "control_planes" {
  value = { for i in aws_instance.control_plane : i.tags["Name"] => "${i.public_ip} (${i.private_ip}, ${i.availability_zone})" }
}

output "workers" {
  value = { for i in aws_instance.worker : i.tags["Name"] => "${i.public_ip} (${i.private_ip}, ${i.availability_zone})" }
}

output "ssh_first_control_plane" {
  value = "ssh -i ${abspath(local_sensitive_file.private_key.filename)} ubuntu@${aws_instance.control_plane[0].public_ip}"
}

output "allowed_cidr" {
  value = local.allowed_cidr
}
