
data "terraform_remote_state" "eks" {
  backend = "local"
 
  config = {
    path = "../eks/terraform.tfstate"
  }
}

// configure kubernetes provider to talk to newly created cluster.
// this requires the aws cli be installed.
provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.eks.endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.eks.name]
  }
}

// for resources we provision, we expect to perform the required k8s annotations
// as we create them.
//
// However for services provisioned by EKS or addons, we need to add the
// annotation ourselves.

resource "kubernetes_annotations" "cni_role" {
  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    namespace = "kube-system"
    name      = "aws-node"
  }
  annotations = {
    "eks.amazonaws.com/role-arn" : data.terraform_remote_state.eks.outputs.pod_roles.kube-system_aws-node.arn
  }
}