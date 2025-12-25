
variable "assume_role" {
  type        = string
  description = "IAM role to assume when calling AWS APIs"
}

variable "k8s_metrics_chart_version" {
  type    = string
  default = "3.13.0"
}

variable "lb_controller_chart_version" {
  type    = string
  default = "1.14.0"
}

variable "envoy_gateway_chart_version" {
  type = string
  default = "1.6.1"
}

variable "karpenter_chart_version" {
  type    = string
  default = "1.8.1"
}