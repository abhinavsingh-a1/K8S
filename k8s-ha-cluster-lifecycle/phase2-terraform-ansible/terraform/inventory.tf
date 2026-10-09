# Hand-off to Ansible: write the inventory with every node's IPs and the
# NLB endpoint, so Terraform and Ansible never get out of sync.

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/hosts.ini.tftpl", {
    control_planes = [
      for i in aws_instance.control_plane : {
        name       = i.tags["Name"]
        public_ip  = i.public_ip
        private_ip = i.private_ip
      }
    ]
    workers = [
      for i in aws_instance.worker : {
        name       = i.tags["Name"]
        public_ip  = i.public_ip
        private_ip = i.private_ip
      }
    ]
    key_file          = abspath(local_sensitive_file.private_key.filename)
    api_endpoint      = aws_lb.this.dns_name
    ingress_node_port = var.ingress_node_port
  })
}
