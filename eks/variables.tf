
variable "region" {
  type = string
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
  default = "1.30"
}

variable "eks_vpc_cni_addon_version" {
  type    = string
  default = "v1.18.3-eksbuild.2"
}

variable "eks_kube_proxy_addon_version" {
  type = string
  default = "v1.30.3-eksbuild.2"
}

variable "eks_csi_addon_version" {
  type    = string
  default = "v1.33.0-eksbuild.1"
}

variable "eks_pod_identity_addon_version" {
  type    = string
  default = "v1.3.0-eksbuild.1"
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

// We've planned out the splits for 2 AZs, even though we're only
// using one
// https://www.davidc.net/sites/default/subnets/subnets.html?network=10.0.0.0&mask=16&division=21.ff4200

variable "vpc_public_subnets" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "vpc_private_subnets" {
  type    = list(string)
  default = ["10.0.4.0/23", "10.0.6.0/23"]
}


variable "vpc_intra_subnets" {
  type    = list(string)
  default = ["10.0.2.0/24", "10.0.3.0/24"]
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
