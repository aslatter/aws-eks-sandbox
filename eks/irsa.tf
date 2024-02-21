
// https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html

// An alternative is https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html,
// however we would still need IRSA for EKS managed addons (and other off-the-shelf services
// which don't yet support pod-identities), so we may as well just use IRSA.
//
// Pod-identities are applied without needing the application-developer to modify their
// Kubernetes yamls, so it might be worth running both in parallel at some point.

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

locals {
  eks_oidc_issuer      = aws_eks_cluster.main.identity[0].oidc[0].issuer
  eks_oidc_issuer_name = replace(local.eks_oidc_issuer, "https://", "")
}

data "tls_certificate" "eks_oidc_issuer" {
  url = local.eks_oidc_issuer
}

// register cluster oidc endpoint with IAM
resource "aws_iam_openid_connect_provider" "eks_irsa" {
  url             = local.eks_oidc_issuer
  thumbprint_list = [data.tls_certificate.eks_oidc_issuer.certificates[0].sha1_fingerprint]
  client_id_list  = ["sts.amazonaws.com"]
}

// allow assuming a role based on external OIDC credentials.
// in this case, the external OIDC provider is the k8s cluster.
data "aws_iam_policy_document" "eks_irsa_trust_policy" {
  for_each = local.eks_pod_role_assignments

  statement {
    sid     = "EKSClusterAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks_irsa.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_issuer_name}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.serviceAccount}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_issuer_name}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_irsa_role" {
  for_each = local.eks_pod_role_assignments

  name_prefix = "eks-${each.key}-"
  path        = "/deployment/"

  permissions_boundary = var.iam_permission_boundary
  // max-session duration?

  assume_role_policy = data.aws_iam_policy_document.eks_irsa_trust_policy[each.key].json
}

resource "aws_iam_role_policy_attachment" "eks_irsa" {
  for_each = merge([
    for k, v in local.eks_pod_role_assignments :
    merge([
      for pk, p in v.policyArns : {
        "${k}-${pk}" : {
          policy : p
          role : aws_iam_role.eks_irsa_role[k].name
        }
      }
    ]...)
  ]...)

  policy_arn = each.value.policy
  role       = each.value.role
}
