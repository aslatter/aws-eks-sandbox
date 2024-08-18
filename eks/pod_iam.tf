
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
    karpenter : {
      namespace : "karpenter"
      serviceAccount : "karpenter"
      // karpenter runs on Fargate which doesn't support pod identity
      // https://github.com/aws/containers-roadmap/issues/2274
      useLegacyIRSA : true
      policyArns : {
        karpenter : aws_iam_policy.karpenter.arn
      }
    }
  }
}

// allow assuming a role based on k8s service account.
// usually this is through EKS Pod Identity, but we allow
// a service-account to opt-in to IRSA if that's all it
// can use.
data "aws_iam_policy_document" "eks_pod_trust_policy" {
  for_each = local.eks_pod_role_assignments

  // there's probably no harm in trusting both methods
  // statically.

  dynamic "statement" {
    for_each = try(each.value.useLegacyIRSA, false) ? [] : [1]
    content {
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
      // we could verify the request-tags to
      // double-check that EKS Pod Auth thinks
      // it is applying permissions to what we
      // think we want. This doesn't actually prevent
      // the service from issuing credentials
      // to the "wrong" client, however, so I'm
      // on the fence.
      # condition {
      #   test     = "StringEquals"
      #   variable = "aws:RequestTag/kubernetes-namespace"
      #   values   = [each.value.namespace]
      # }
      # condition {
      #   test     = "StringEquals"
      #   variable = "aws:RequestTag/kubernetes-service-account"
      #   values   = [each.value.serviceAccount]
      # }
    }
  }

  dynamic "statement" {
    for_each = try(each.value.useLegacyIRSA, false) ? [1] : []
    content {
      sid     = "EKSIrsaAssumeRole"
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
  for_each        = { for k, v in local.eks_pod_role_assignments : k => v if !try(v.useLegacyIRSA, false) }
  cluster_name    = aws_eks_cluster.main.name
  namespace       = each.value.namespace
  service_account = each.value.serviceAccount
  role_arn        = aws_iam_role.eks_pod_role[each.key].arn
}

//
// IRSA stuff for services which don't/can't support pod identity
// https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
//

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
