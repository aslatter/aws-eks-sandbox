
// https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html

locals {
  eks_oidc_issuer = aws_eks_cluster.main.identity[0].oidc[0].issuer
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

// insert role-assignments here ...
