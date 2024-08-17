
// https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html

locals {
  // map of k8s service-accounts and the IAM policies we
  // would like to grant them access to.
  eks_pod_role_assignments = {
    cni : {
      namespace : "kube-system"
      serviceAccount : "aws-node"
      policyArns : {
        "cni" : "${local.iam_role_policy_prefix}/AmazonEKS_CNI_Policy"
        "cni_ipv6" : aws_iam_policy.cni_ipv6_policy.arn
        "restrict_eni_access" : aws_iam_policy.restrict_eni_access.arn
      }
    }
    lb_controler : {
      namespace : "kube-system"
      serviceAccount : "aws-lb-controller"
      policyArns : {
        lb_controler : aws_iam_policy.lb_controler.arn
      }
    }
    csi : {
      namespace : "kube-system"
      serviceAccount : "ebs-csi-controller-sa"
      policyArns : {
        "csi_policy" : "${local.iam_role_policy_prefix}/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
    cas : {
      namespace : "kube-system"
      serviceAccount : "cluster-autoscaler"
      policyArns : {
        cas : aws_iam_policy.cluster_autoscaler.arn
      }
    }
  }
}

// allow assuming a role based on external OIDC credentials.
// in this case, the external OIDC provider is the k8s cluster.
data "aws_iam_policy_document" "eks_pod_trust_policy" {
  for_each = local.eks_pod_role_assignments

  statement {
    sid     = "EKSPodIdentityAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_eks_cluster.main.arn]
    }
  }
}

resource "aws_iam_role" "eks_pod_role" {
  for_each = local.eks_pod_role_assignments

  name_prefix = "eks-${each.key}-"
  path        = "/deployment/"

  permissions_boundary = var.iam_permission_boundary
  // max-session duration?

  assume_role_policy = data.aws_iam_policy_document.eks_pod_trust_policy[each.key].json
}

resource "aws_iam_role_policy_attachment" "eks_pod_roles" {
  for_each = merge([
    for k, v in local.eks_pod_role_assignments :
    merge([
      for pk, p in v.policyArns : {
        "${k}-${pk}" : {
          policy : p
          role : aws_iam_role.eks_pod_role[k].name
        }
      }
    ]...)
  ]...)

  policy_arn = each.value.policy
  role       = each.value.role
}

resource "aws_eks_pod_identity_association" "eks_pod_identity_association" {
  for_each        = local.eks_pod_role_assignments
  cluster_name    = aws_eks_cluster.main.name
  namespace       = each.value.namespace
  service_account = each.value.serviceAccount
  role_arn        = aws_iam_role.eks_pod_role[each.key].arn
}
