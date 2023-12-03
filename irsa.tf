
// https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html

locals {
    eks_pod_role_assignments = {
        cni : {
            namespace : "kube-system"
            serviceAccount : "aws-node"
            policyArns : [
                "${local.iam_role_policy_prefix}/AmazonEKS_CNI_Policy"
            ]
        }
    }
}

locals {
  eks_oidc_issuer = aws_eks_cluster.main.identity[0].oidc[0].issuer
  eks_oidc_issuer_name = replace(local.eks_oidc_issuer, "https://", "")
}

data "tls_certificate" "eks_oidc_issuer" {
  url = local.eks_oidc_issuer
}

// register eks oidc endpoint with IAM
resource "aws_iam_openid_connect_provider" "eks_irsa" {
  url = local.eks_oidc_issuer
  thumbprint_list = [data.tls_certificate.eks_oidc_issuer.certificates[0].sha1_fingerprint]
  client_id_list = ["sts.${data.aws_partition.current.dns_suffix}"]
}

// allow assuming a role based on external OIDC credentials.
// in this case, the external OIDC provider is the k8s cluster.
data "aws_iam_policy_document" "eks_irsa_trust_policy" {
  for_each = local.eks_pod_role_assignments

  statement {
    sid     = "EKSClusterAssumeRole"
    effect = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks_irsa.arn]
    }

    condition {
      test = "StringEquals"
      variable = "${local.eks_oidc_issuer_name}:sub"
      values = ["system:serviceaccount:${each.value.namespace}:${each.value.serviceAccount}"]
    }
    condition {
      test = "StringEquals"
      variable = "${local.eks_oidc_issuer_name}:aud"
      values = ["sts.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "eks_irsa_role" {
    for_each = local.eks_pod_role_assignments

    name_prefix = "eks-${each.key}-"

    // permission boundaries?
    // max-session duration?

    assume_role_policy = data.aws_iam_policy_document.eks_irsa_trust_policy[each.key].json
}

resource "aws_iam_role_policy_attachment" "eks_irsa" {
  for_each = merge([
    for k, v in local.eks_pod_role_assignments :
    merge([
        for p in v.policyArns : {
            "${k}-${sha1(p)}" : {
                policy : p
                role : aws_iam_role.eks_irsa_role[k].name
            }
        }
    ]...)
  ]...)

  policy_arn = each.value.policy
  role = each.value.role
}

// output role ARNs
output "pod_roles" {
  value = {
    for k, v in aws_iam_role.eks_irsa_role :
    "${local.eks_pod_role_assignments[k].namespace}_${local.eks_pod_role_assignments[k].serviceAccount}" => {
        arn : v.arn
    }
  }
}

// for resources we provision, we expect to perform the required k8s annotations
// as we create them.
//
// However for services provisioned by EKS or addons, we need to add the
// annotation ourselves.

resource "kubernetes_annotations" "cni_role" {
  api_version = "v1"
  kind = "ServiceAccount"
  metadata {
    namespace = local.eks_pod_role_assignments.cni.namespace
    name = local.eks_pod_role_assignments.cni.serviceAccount
  }
  annotations = {
    "eks.amazonaws.com/role-arn" : aws_iam_role.eks_irsa_role["cni"].arn
  }
}