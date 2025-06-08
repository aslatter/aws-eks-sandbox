
variable "assume_role" {
  type        = string
  description = "IAM role to assume when calling AWS APIs"
}

variable "k8s_metrics_chart_version" {
  type    = string
  default = "3.12.2"
}

variable "lb_controller_chart_version" {
  type    = string
  default = "1.13.2"
}

variable "nginx_ingress_chart_version" {
  type    = string
  default = "4.12.3"
}

variable "karpenter_chart_version" {
  type    = string
  default = "1.5.0"
}