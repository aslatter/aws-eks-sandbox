
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks.arn
  version  = var.eks_k8s_version

  bootstrap_self_managed_addons = false

  upgrade_policy {
    support_type = "STANDARD"
  }

  compute_config {
    enabled = true
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }

  storage_config {
    block_storage {
      enabled = true
    }
  }

  // TODO - enabled cluster log types?

  vpc_config {
    // default behavior is to apply this SG to the control-plane
    // ENIs provisioned in our VPC and for the nodes, however
    // we use a separate SG for nodes in our node-launch-templates.
    security_group_ids = [aws_security_group.eks_cluster.id]
    // determines the AZs to provision the control-plane into. We must
    // have at least two AZs specified here. We can provision nodes into
    // more or fewer zones, and onto completely different subnets (as long
    // as the routes and SGs allow for communication).
    subnet_ids = aws_subnet.intra[*].id
    // because we're setting public_access_cidrs we either
    // need to enable private access, or add the NAT gateway outbound IPs
    // to the public-access-cidrs list.
    public_access_cidrs     = var.public_access_cidrs
    endpoint_private_access = true
  }

  access_config {
    authentication_mode = "API"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks,
    aws_vpc_security_group_ingress_rule.eks_cluster,
    aws_vpc_security_group_ingress_rule.eks_nodes,
  ]

  tags = {
    Name : "eks"
  }
}

//
// IAM Cluster Auth
//
// This setup is for using IAM to access the k8s
// API endpoint itself.
//

// unlike with IAM policies we can only grant specific
// principals access to the cluster. So we need to look
// up the specific SSO principals which represent SSO
// access.
data "aws_iam_roles" "sso_cluster_admin_access" {
  for_each    = toset(var.cluster_admin_acess_permission_sets)
  name_regex  = "AWSReservedSSO_${each.value}_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

locals {
  cluster_admin_access_role_arns = concat(
    [var.assume_role],
    flatten(values(data.aws_iam_roles.sso_cluster_admin_access)[*].arns),
  )
}

// allow our nodes to talk to the control-plane (auto-mode)
resource "aws_eks_access_entry" "node" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2"
}

// allow our nodes to talk to the control-plane (auto-mode)
resource "aws_eks_access_policy_association" "node" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.node.arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSAutoNodePolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.node]
}

// I would have expected this to have been set up for use,
// at least for the principal which created the cluster?
resource "aws_eks_access_entry" "main" {
  for_each      = toset(local.cluster_admin_access_role_arns)
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "main" {
  for_each      = toset(local.cluster_admin_access_role_arns)
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

//
// IAM
//
// Create IAM role for the cluster control-plane itself.
//

data "aws_iam_policy_document" "eks_assume_role_policy" {
  statement {
    sid = "EKSClusterAssumeRole"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks" {
  name_prefix = "eks-${local.cluster_name}"
  path        = "/deployment/"

  assume_role_policy    = data.aws_iam_policy_document.eks_assume_role_policy.json
  permissions_boundary  = var.iam_permission_boundary
  force_detach_policies = true // I don't think we need this?

  // https://github.com/terraform-aws-modules/terraform-aws-eks/issues/920

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  iam_role_policy_prefix = "arn:${data.aws_partition.current.partition}:iam::aws:policy"
}

// https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html
resource "aws_iam_role_policy_attachment" "eks" {
  // it would be nice to somehow scope this to just the ECS/VPC resources associated
  // with this cluster? Maybe?
  for_each = {
    AmazonEKSComputePolicy       = "${local.iam_role_policy_prefix}/AmazonEKSComputePolicy",
    AmazonEKSBlockStoragePolicy  = "${local.iam_role_policy_prefix}/AmazonEKSBlockStoragePolicy",
    AmazonEKSLoadBalancingPolicy = "${local.iam_role_policy_prefix}/AmazonEKSLoadBalancingPolicy",
    AmazonEKSNetworkingPolicy    = "${local.iam_role_policy_prefix}/AmazonEKSNetworkingPolicy",
    AmazonEKSClusterPolicy       = "${local.iam_role_policy_prefix}/AmazonEKSClusterPolicy",
    restrict_eni_access          = aws_iam_policy.restrict_eni_access.arn,
    allow_eks_auto_mode_tags     = aws_iam_policy.allow_eks_auto_mode_tags.arn,
  }

  policy_arn = each.value
  role       = aws_iam_role.eks.name
}
