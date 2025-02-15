
variable "region" {
  type = string
}

variable "global_region" {
  type    = string
  default = "us-east-1"
}

variable "assume_role" {
  type        = string
  description = "IAM role to assume when calling AWS APIs"
}

variable "iam_permission_boundary" {
  type        = string
  default     = null
  description = "Permission-boundary to assign to created IAM roles"
}

variable "cluster_admin_acess_permission_sets" {
  type        = list(string)
  default     = ["AdministratorAccess"]
  description = "SSO permission-sets with admin-access to the k8s cluster"
}

variable "aws_account_id" {
  type = string
}

variable "eks_k8s_version" {
  type    = string
  default = "1.32"
}

variable "eks_csi_addon_version" {
  type    = string
  default = "v1.35.0-eksbuild.1"
}

variable "cluster_az_count" {
  type        = number
  default     = 2
  description = "number of availability zones to place control-plan interfaces into"
}

variable "node_az_count" {
  type        = number
  default     = 1
  description = "number of availability zones to place worker-nodes into"
}

variable "vpc_cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

// TODO - secondary CIDR blocks ?

// We've planned out the splits for 3 AZs, even though we're only
// using one.

variable "vpc_public_subnets" {
  type    = list(string)
  default = ["10.0.96.0/22", "10.0.100.0/22", "10.0.104.0/22"]
}

variable "vpc_private_subnets" {
  type    = list(string)
  default = ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19"]
}

variable "vpc_intra_subnets" {
  type    = list(string)
  default = ["10.0.108.0/22", "10.0.112.0/22", "10.0.116.0/22"]
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = []
  description = "IPv4 CIDR-blocks from which to allow inbound access to resources"
}

variable "dns" {
  type = object({
    zone_name = optional(string)
  })
  default = {}
}
