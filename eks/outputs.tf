
output "info" {
  value = {
    resourceGroup = {
      name = aws_resourcegroups_group.group.name
      id   = aws_resourcegroups_group.group.arn
    }
    region = var.region
  }
}

output "azs" {
  value = local.azs
}

output "eks" {
  value = {
    name                   = aws_eks_cluster.main.name
    endpoint               = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = aws_eks_cluster.main.certificate_authority[0].data
    version                = aws_eks_cluster.main.version
  }
}

// output role ARNs
output "pod_roles" {
  value = {
    for k, v in aws_iam_role.eks_irsa_role :
    "${local.eks_pod_role_assignments[k].namespace}_${local.eks_pod_role_assignments[k].serviceAccount}" => {
      arn : v.arn
    }
  }
}

output "ipv6_cidr_block" {
  value = var.ipv6_enable ? aws_vpc.main.ipv6_cidr_block : null
}

output "vpc" {
  value = {
    vpc_id : aws_vpc.main.id
    nodes_security_group_id : aws_security_group.eks_nodes.id
    nodes_subnet_ids : aws_subnet.private[*].id
  }
}