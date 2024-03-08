terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.39"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]
  assume_role {
    role_arn     = var.assume_role
    session_name = "deploy"
  }
  default_tags {
    tags = {
      "group" = local.group_name
    }
  }
}

data "aws_partition" "current" {}

// Find AZs to provision into
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "random_shuffle" "az" {
  input = data.aws_availability_zones.available.names
}

locals {
  azs = slice(random_shuffle.az.result, 0, max(var.cluster_az_count, var.node_az_count))
}

data "terraform_remote_state" "init" {
  backend = "local"

  config = {
    path = "../init/terraform.tfstate"
  }
}

locals {
  entropy      = data.terraform_remote_state.init.outputs.entropy
  cluster_name = data.terraform_remote_state.init.outputs.name
  group_name   = data.terraform_remote_state.init.outputs.name
}

// We play some tricks to get all provisioned
// resources into a single resource group, for easy
// visibility into separate deployments within the
// same account.
//
// I wanted to dynamically add entropy to the tag-value,
// but that was running into issues.

resource "aws_resourcegroups_group" "group" {
  name = local.group_name
  resource_query {
    query = jsonencode({
      ResourceTypeFilters : [
        "AWS::AllSupported"
      ],
      TagFilters : [
        {
          Key : "group",
          Values : [local.group_name]
        }
      ]
    })
  }

  tags = {
    Name = "rg"
  }
}


