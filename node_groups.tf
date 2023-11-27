
locals {
  // TODO - move to variables?
  eks_node_group_defaults = {
    ami_type = "AL2_x86_64"
  }
  eks_node_groups = {
    one : {
      name : "node-group-1"

      instance_types : ["t3a.small"]

      min_size : 0
      max_size : 1
      desired_size : 1
      // taints etc?
    }
    two : {
      name : "node-group-2"

      instance_types : ["t3a.small"]

      min_size : 0
      max_size : 1
      desired_size : 0
    }
  }
}

resource "aws_launch_template" "node" {
  network_interfaces {
    security_groups = [aws_security_group.eks_nodes.id]
  }
}

// consider two node_group blocks for if we should
// ignore desired-size?
resource "aws_eks_node_group" "main" {
  for_each = local.eks_node_groups

  cluster_name  = local.cluster_name
  node_role_arn = aws_iam_role.node[each.key].arn
  subnet_ids    = aws_subnet.private[*].id

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  node_group_name_prefix = "${each.value.name}-"

  launch_template {
    id = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  ami_type = local.eks_node_group_defaults.ami_type
  // release version?
  // version?

  // capacity-type
  // disk-size
  // force-update-version
  // instance-types

  // remote access

  // taints

  // update config

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      scaling_config[0].desired_size,
    ]
  }

  tags = {
    Name : each.value.name
  }
}

data "aws_iam_policy_document" "node_assume_role_policy" {
  statement {
    sid     = "EKSNodeAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

// there isn't much value at the moment for creating a
// role per node-group?
resource "aws_iam_role" "node" {
  for_each = local.eks_node_groups
 
  name_prefix = "${each.value.name}-"
  // path
  description = "Node role for ${each.value.name}"

  assume_role_policy    = data.aws_iam_policy_document.node_assume_role_policy.json
  // permission boundary
  force_detach_policies = true

  tags = {
    Name : "${each.value.name}"
  }
}

// https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group
resource "aws_iam_role_policy_attachment" "node" {
  for_each = merge([
    for group_key, group in local.eks_node_groups : merge([
      for role in ["AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryReadOnly"] :
        {
          "${group_key}-${role}": {
            group : group_key
            role : role
          }
        }
    ]...)
  ]...)
  
  policy_arn = "${local.iam_role_policy_prefix}/${each.value.role}"
  role       = aws_iam_role.node[each.value.group].name
}

// additional role-policy-attachments?
