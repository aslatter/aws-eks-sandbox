
resource "aws_eks_fargate_profile" "main" {
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "main-${local.entropy}"
  pod_execution_role_arn = aws_iam_role.fargate_execution.arn
  subnet_ids             = aws_subnet.private[*].id

  selector {
    namespace = "karpenter"
  }
}

data "aws_iam_policy_document" "fargate_execution_trust_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:eks:${var.region}:${var.aws_account_id}:fargateprofile/${aws_eks_cluster.main.name}/*"]
    }
  }
}

resource "aws_iam_role" "fargate_execution" {
  name_prefix          = "fargate_execution-"
  path                 = "/deployment/"
  permissions_boundary = var.iam_permission_boundary
  assume_role_policy   = data.aws_iam_policy_document.fargate_execution_trust_policy.json
}

resource "aws_iam_role_policy_attachment" "fargate_karpenter" {
  role       = aws_iam_role.fargate_execution.name
  policy_arn = "${local.iam_role_policy_prefix}/AmazonEKSFargatePodExecutionRolePolicy"
}
