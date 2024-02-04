
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

variable "cluster_autoscaler_chart_version" {
  type = string
  default = "9.34.1"
}

variable "cluster_autoscaler_image_tag" {
  type = string
  default = "v1.29.0"
}
