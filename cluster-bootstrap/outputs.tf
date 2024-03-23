output "control_plane_ip" {
  value = aws_instance.control_plane.public_ip
}

output "node_ips" {
  value = aws_instance.node[*].public_ip
}

output "cluster_name" {
  value = var.cluster_name
}

output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "public_subnets_ids" {
  value = local.public_subnets_ids
}

output "worker_nodes_ids" {
  value = aws_instance.node[*].id
}
