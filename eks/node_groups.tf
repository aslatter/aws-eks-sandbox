
locals {
  // This could come in as a variable
  eks_node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"
  }
  eks_node_groups = {
    one : {
      name : "node-group-1"
      enabled : false

      // AWS allows apecifying multiple instance-types
      // to use.
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

// grab default tags we supplied to provider to we
// can pass them in to the launch-template
data "aws_default_tags" "tags" {}

resource "aws_launch_template" "node" {

  // assign to node sg (this also becomes the pod sg)
  vpc_security_group_ids = [aws_security_group.eks_nodes.id]

  // require imdsv2, set hop-limit to 1. this prevents
  // pods not using host-networking from accessing IMDS.
  //
  // TODO - should be default now, can remove.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  dynamic "tag_specifications" {
    // attach our tracking-tags to everything interesting
    // created by the managed node group. This doesn't
    // actually work for network-interfaces :-(
    //
    // https://github.com/aws/containers-roadmap/issues/1496
    for_each = ["instance", "volume", "network-interface"]
    content {
      resource_type = tag_specifications.value
      tags          = data.aws_default_tags.tags.tags
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
  node_role_arn = aws_iam_role.node.arn
  subnet_ids    = aws_subnet.private[*].id

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

  // I have no idea how to manage node-AMI versions
  ami_type = local.eks_node_group_defaults.ami_type

  // the community module threads this through a
  // time_sleep resource
  version = aws_eks_cluster.main.version

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
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    // we need to make sure we're not creating pods prior to the pod-identity
    // association - otherwise the builtin web-hooks won't know to modify the
    // pods to be aware of their identity-source.
    aws_eks_pod_identity_association.eks_pod_identity_association,
  ]
}
