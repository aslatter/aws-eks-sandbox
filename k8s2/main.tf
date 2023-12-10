
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

// wire helm up the same way we would k8s
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

// install the AWS load-balancer ingress-controller
// we won't actually use it as an ingress, but we will
// use its CRDs to link services to existing NLBs.

resource "helm_release" "lb_controller" {
  name = "aws-load-balancer-controller"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.6.2"

  namespace = "kube-system"

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

// k8s metrics server
resource "helm_release" "k8s_metrics" {
  name = "k8s-metrics-server"

  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.11.0"

  namespace = "kube-system"

}