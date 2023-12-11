
variable "region" {
  type    = string
  default = "us-east-2"
}

variable "group" {
  type    = string
  default = "test-deployment"
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

variable "vpc_public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24"]
}

variable "vpc_ipv6_public_subnets" {
  type    = list(number)
  default = [0]
}

variable "vpc_private_subnets" {
  type    = list(string)
  default = ["10.0.2.0/24"]
}


variable "vpc_ipv6_private_subnets" {
  type    = list(number)
  default = [1]
}

variable "vpc_intra_subnets" {
  type    = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "vpc_ipv6_intra_subnets" {
  type    = list(number)
  default = [2, 3]
}
variable "eks_k8s_version" {
  type    = string
  default = "1.28"
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR-blocks from which to allow inbound access to resources"
}

variable "public_access_cidrs_ipv6" {
  type        = list(string)
  default     = ["::/0"]
  description = "IPv6 CIDR-blocks from which to allow inbound access to resources"
}

variable "ipv6_enable" {
  type        = bool
  default     = false
  description = "create dual-stack networking and use ipv6 for pod-to-pod traffic"
}