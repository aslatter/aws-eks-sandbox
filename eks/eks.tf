
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks.arn
  version  = var.eks_k8s_version

  // TODO - enabled cluster log types?

  kubernetes_network_config {
    ip_family = var.ipv6_enable ? "ipv6" : null
  }

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
// IAM
//

data "aws_iam_policy_document" "eks_assume_role_policy" {
  statement {
    sid     = "EKSClusterAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks" {
  name_prefix = "${local.cluster_name}-cluster-"

  assume_role_policy    = data.aws_iam_policy_document.eks_assume_role_policy.json
  permissions_boundary  = aws_iam_policy.eks_permission_boundary.arn
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
    AmazonEKSClusterPolicy         = "${local.iam_role_policy_prefix}/AmazonEKSClusterPolicy",
    AmazonEKSVPCResourceController = "${local.iam_role_policy_prefix}/AmazonEKSVPCResourceController",
    restrict_eni_access            = aws_iam_policy.restrict_eni_access.arn,
  }

  policy_arn = each.value
  role       = aws_iam_role.eks.name
}

//
// Add-ons
//

resource "aws_eks_addon" "vpc-cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  addon_version = var.eks_cni_addon_version

  // note! this is using IRSA, not EKS Pod Identities (so requires
  // OIDC-trust-setup).
  //
  // https://docs.aws.amazon.com/eks/latest/userguide/managing-add-ons.html
  service_account_role_arn = aws_iam_role.eks_irsa_role["cni"].arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_iam_role_policy_attachment.eks_irsa]
}

resource "aws_eks_addon" "csi" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = var.eks_csi_addon_version

  service_account_role_arn = aws_iam_role.eks_irsa_role["csi"].arn

  configuration_values = jsonencode({
    controller : {
      extraVolumeTags : data.aws_default_tags.tags.tags
    }
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_irsa,

    // internally, AWS applies a helm-chart with a deployment
    // and waits for it to become ready, which can't happen
    // until after we have nodes so we may as well wait for that.
    aws_eks_node_group.main,
  ]
}

//
// IAM Cluster Auth
//

// We can allow AWS IAM auth or OIDC auth to the EKS control-plane
// - https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html
// - https://docs.aws.amazon.com/eks/latest/userguide/authenticate-oidc-identity-provider.html
//
// (this is not IRSA)

// if we want to re-build the aws-auth configmap, we will need to manaully add-in
// the EC2 node-instance roles :-(
