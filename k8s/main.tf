
data "terraform_remote_state" "init" {
  backend = "local"

  config = {
    path = "../init/terraform.tfstate"
  }
}

data "terraform_remote_state" "eks" {
  backend = "local"

  config = {
    path = "../eks/terraform.tfstate"
  }
}

locals {
  cluster_name = data.terraform_remote_state.init.outputs.name
}

// configure kubernetes provider to talk to newly created cluster.
// this requires the aws cli be installed.
provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.eks.endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
  }
}

// IRSA requires a service-account annotation to tell the mutating admission
// controller to wire things up for the pods. Normally, we would expect the
// author of an application to supply this annotation.
//
// However for services provisioned by EKS or addons, we need to add the
// annotation ourselves.
//
// Here, we're wiring up IRSA to the CNI service-account. This needs to happen
// after we create the control-plane but before we create any nodes (thankfully
// the IRSA web-hook doesn't run on our compute - we'd be pretty stuck if that
// were the case)/
//
// This issue makes reference to the CNI boostrapping issue (but isn't really about it):
//   https://github.com/aws/containers-roadmap/issues/1666
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
