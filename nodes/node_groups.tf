
locals {
  // TODO - move to variables?
  eks_node_group_defaults = {
    ami_type = "AL2_x86_64"
  }
  eks_node_groups = {
    one : {
      name : "node-group-1"

      instance_types : ["t3a.small", "t3.small"]

      min_size : 0
      max_size : 1
      desired_size : 1
      // taints etc?
    }
    two : {
      name : "node-group-2"
      enabled : false

      instance_types : ["t3a.small", "t3.small"]

      min_size : 0
      max_size : 1
      desired_size : 0
    }
  }
}

resource "aws_launch_template" "node" {
  // install SSM-agent
  user_data = base64encode(file("${path.module}/init_node.sh"))

  // assign to custom sg
  vpc_security_group_ids = [local.nodes_security_group_id]

  // require imdsv2, set hop-limit to 1
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  dynamic "tag_specifications" {
    for_each = ["instance", "volume", "network-interface"]
    content {
      resource_type = tag_specifications.value
      tags = {
        "group" = local.group_name
      }
    }
  }

  tags = {
    Name : "lt"
  }
}

// consider two node_group blocks for if we should
// ignore desired-size?
resource "aws_eks_node_group" "main" {
  for_each = { for k, v in local.eks_node_groups : k => v if lookup(v, "enabled", true) }

  cluster_name  = local.cluster_name
  node_role_arn = aws_iam_role.node[each.key].arn
  subnet_ids    = local.nodes_subnet_ids

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  node_group_name_prefix = "${each.value.name}-"

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  ami_type = local.eks_node_group_defaults.ami_type
  // release version?

  // the community module threads this through a
  // time_sleep resource
  version = local.k8s_version

  instance_types = each.value.instance_types

  // capacity-type
  // disk-size
  // force-update-version
  // instance-types

  // remote access

  // taints

  // update config

  tags = {
    Name : each.value.name
    "group" = local.group_name
  }

  lifecycle {
    create_before_destroy = true
    # ignore_changes = [
    #   scaling_config[0].desired_size,
    # ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
  ]
}

locals {
  iam_role_policy_prefix = "arn:${data.aws_partition.current.partition}:iam::aws:policy"
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
  for_each = { for k, v in local.eks_node_groups : k => v if lookup(v, "enabled", true) }

  name_prefix = "${each.value.name}-"
  // path
  description = "Node role for ${each.value.name}"

  assume_role_policy = data.aws_iam_policy_document.node_assume_role_policy.json
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
      for role in [
        // NOTE! these policies give us account-wide access
        // to things! custom policies or permission boundaries
        // count scope this down.

        // NOTE! these policies are accessible from the node
        // IMDS endpoint, which is accessible from pods
        // using host-networking.

        // required EKS policies
        "AmazonEKSWorkerNodePolicy",
        "AmazonEC2ContainerRegistryReadOnly",

        // required for system management
        "CloudWatchAgentServerPolicy",
        "AmazonSSMManagedInstanceCore",
      ] :
      {
        "${group_key}-${role}" : {
          group : group_key
          role : role
        }
      }
    ]...)
  if lookup(group, "enabled", true) ]...)

  policy_arn = "${local.iam_role_policy_prefix}/${each.value.role}"
  role       = aws_iam_role.node[each.value.group].name
}

// additional role-policy-attachments?
