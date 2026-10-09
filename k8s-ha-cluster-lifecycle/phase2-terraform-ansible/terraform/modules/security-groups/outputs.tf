output "nodes_sg_id" {
  value = aws_security_group.nodes.id
}

output "nlb_sg_id" {
  value = aws_security_group.nlb.id
}
