# Hand-off to Ansible. Hosts are discovered by the aws_ec2 dynamic inventory
# (tags), so Terraform only publishes the NON-secret values Ansible needs.
# Secrets never go here: they live in Ansible Vault / Secrets Manager.

resource "local_file" "ansible_group_vars" {
  filename        = "${path.module}/../../../ansible/inventories/${var.environment}/group_vars/all/terraform.yml"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/terraform_vars.yml.tftpl", {
    region            = var.region
    project           = var.project
    environment       = var.environment
    api_endpoint      = module.nlb.dns_name
    ingress_node_port = var.ingress_node_port
    ssh_key_secret    = module.ssh_key.secret_name
    vpc_cidr          = module.network.vpc_cidr
  })
}
