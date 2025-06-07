
terraform {
  required_version = ">= 0.13"

  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.0"
    }
  }
}

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
  aws_region                = data.terraform_remote_state.eks.outputs.info.region
  cluster_name              = data.terraform_remote_state.init.outputs.name
  cluster_endpoint          = data.terraform_remote_state.eks.outputs.eks.endpoint
  cluster_ca_certificate    = data.terraform_remote_state.eks.outputs.eks.cluster_ca_certificate
  cluster_version           = data.terraform_remote_state.eks.outputs.eks.version
  default_tags              = data.terraform_remote_state.init.outputs.default_tags
  nlb_target_group_http_arn = data.terraform_remote_state.eks.outputs.vpc.nlb_target_group_http_arn
  nodes_security_group_id   = data.terraform_remote_state.eks.outputs.vpc.nodes_security_group_id
}

locals {
  // we auth to k8s with a token acquired from the aws cli.
  // these are the args we pass to the cli to get a token k8s
  // will understand.
  aws_cli_args = [
    "eks", "get-token",
    "--region", local.aws_region,
    "--cluster-name", local.cluster_name,
    "--role-arn", var.assume_role,
  ]
}

// configure kubernetes provider to talk to newly created cluster.
// this requires the aws cli be installed.
provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.aws_cli_args
  }
}

provider "kubectl" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.aws_cli_args
  }

  load_config_file = false
}

// wire helm up the same way we would k8s
provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.aws_cli_args
    }
  }
}
