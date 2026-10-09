output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "One per AZ, in AZ order"
  value       = aws_subnet.public[*].id
}

output "azs" {
  value = local.azs
}
