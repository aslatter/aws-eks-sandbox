terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = local.region
  default_tags {
    tags = {
      "group" = local.group_name
    }
  }
}

data "aws_partition" "current" {}

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
  entropy      = data.terraform_remote_state.init.outputs.entropy
  cluster_name = data.terraform_remote_state.init.outputs.name
  group_name   = data.terraform_remote_state.init.outputs.name

  region                        = data.terraform_remote_state.eks.outputs.info.region
  permission_bounary_policy_arn = data.terraform_remote_state.eks.outputs.info.permission_bounary_policy_arn

  nodes_security_group_id = data.terraform_remote_state.eks.outputs.vpc.nodes_security_group_id
  nodes_subnet_ids        = data.terraform_remote_state.eks.outputs.vpc.nodes_subnet_ids
  k8s_version             = data.terraform_remote_state.eks.outputs.eks.version
}