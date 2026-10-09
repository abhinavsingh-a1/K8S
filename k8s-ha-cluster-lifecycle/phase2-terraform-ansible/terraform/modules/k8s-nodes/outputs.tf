output "instance_ids" {
  value = aws_instance.this[*].id
}

output "nodes" {
  description = "name => IPs and AZ"
  value = {
    for i in aws_instance.this : i.tags["Name"] => {
      id         = i.id
      public_ip  = i.public_ip
      private_ip = i.private_ip
      az         = i.availability_zone
    }
  }
}
