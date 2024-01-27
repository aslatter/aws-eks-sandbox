

variable "k8s_metrics_chart_version" {
  type    = string
  default = "3.11.0"
}

variable "lb_controller_chart_version" {
  type    = string
  default = "1.6.2"
}

variable "nginx_ingress_chart_version" {
  type    = string
  default = "4.9.1"
}
