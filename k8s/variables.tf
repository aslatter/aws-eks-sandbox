
variable "assume_role" {
  type        = string
  description = "IAM role to assume when calling AWS APIs"
}

variable "k8s_metrics_chart_version" {
  type    = string
  default = "3.12.1"
}

variable "lb_controller_chart_version" {
  type    = string
  default = "1.8.2"
}

variable "nginx_ingress_chart_version" {
  type    = string
  default = "4.11.2"
}

variable "karpenter_chart_version" {
  type = string
  default = "1.0.0"
}