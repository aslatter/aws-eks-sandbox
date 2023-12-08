
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
  group_name   = data.terraform_remote_state.init.outputs.name
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

// provide same config for helm
provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.eks.outputs.eks.endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.eks.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
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
  kind        = "ServiceAccount"
  metadata {
    namespace = "kube-system"
    name      = "aws-node"
  }
  annotations = {
    "eks.amazonaws.com/role-arn" : data.terraform_remote_state.eks.outputs.pod_roles.kube-system_aws-node.arn
  }
}

// install the AWS load-balancer ingress-controller
// we won't actually use it as an ingress, but we will
// use its CRDs to link services to existing NLBs.

resource "helm_release" "lb_controller" {
  name = "aws-load-balancer-controller"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.6.2"

  namespace = "kube-system"

  // we're currently staging this ahead of creating any
  // cluster-nodes, so these nodes will never come ready
  // during initial creation.
  wait = false

  values = [jsonencode({
    clusterName : local.cluster_name
    vpcId : data.terraform_remote_state.eks.outputs.vpc.vpc_id
    // recommended for use with AWS CNI
    defaultTargetType : "ip"

    // we don't plan on having the controller actually provision
    // AWS resources, but just in case we should tag them.
    defaultTags : {
      group : local.group_name
    }

    // configure SA for IRSA
    serviceAccount : {
      name : "aws-lb-controller"
      annotations : {
        "eks.amazonaws.com/role-arn" : data.terraform_remote_state.eks.outputs.pod_roles.kube-system_aws-lb-controller.arn
      }
    }
  })]
}