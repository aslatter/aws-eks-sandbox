terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.26"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "group" = var.group
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

resource "random_string" "suffix" {
  length  = 8
  special = false
}

locals {
  entropy = random_string.suffix.result
}

// We play some tricks to get all provisioned
// resources into a single resource group, for easy
// visibility into separate deployments within the
// same account.
//
// I wanted to dynamically add entropy to the tag-value,
// but that was running into issues.

resource "aws_resourcegroups_group" "group" {
  name = var.group
  resource_query {
    query = jsonencode({
      ResourceTypeFilters : [
        "AWS::AllSupported"
      ],
      TagFilters : [
        {
          Key : "group",
          Values : [var.group]
        }
      ]
    })
  }

  tags = {
    Name = "rg"
  }
}


