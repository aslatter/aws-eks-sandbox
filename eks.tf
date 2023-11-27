
locals {
  cluster_name        = "${var.eks_cluster_name}-${local.entropy}"
  public_access_cidrs = concat(var.public_access_cidrs, [for ip in aws_eip.nat : "${ip.public_ip}/32"])
}

resource "aws_eks_cluster" "main" {
  // count    = 0
  name     = local.cluster_name
  role_arn = aws_iam_role.eks.arn
  version  = var.eks_k8s_version
  // TODO - enabled cluster log types?

  vpc_config {
    # security_group_ids = [aws_security_group.eks_cluster.id]
    // do I need to put my node subnets in this list?
    subnet_ids = aws_subnet.intra[*].id
    // TODO private endpoint for worker-node access?
    public_access_cidrs = local.public_access_cidrs
    // because we're setting public_access_cidrs we either
    // need to enable private access, or add the NAT gateway outbound IPs
    // to the public-access-cidrs list.
    endpoint_private_access = true
  }

  // TODO - encryption_config

  depends_on = [
    aws_iam_role_policy_attachment.eks,
    aws_security_group_rule.eks_cluster,
    aws_security_group_rule.eks_nodes,
  ]
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
      identifiers = ["eks.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "eks" {
  name_prefix = "${local.cluster_name}-cluster"

  assume_role_policy = data.aws_iam_policy_document.eks_assume_role_policy.json
  // permissions_boundary  = null
  force_detach_policies = true

  # https://github.com/terraform-aws-modules/terraform-aws-eks/issues/920

  // tags = {}
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
  }

  policy_arn = each.value
  role       = aws_iam_role.eks.name
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

// TODO - IRSA
