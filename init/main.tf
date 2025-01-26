
resource "random_string" "suffix" {
  length  = 12
  special = false
  upper   = false
}

output "entropy" {
  value = random_string.suffix.result
}

variable "name_prefix" {
  default = "learning"
}

output "name_prefix" {
  value = var.name_prefix
}

locals {
  name = "${var.name_prefix}-${random_string.suffix.result}"
}

output "name" {
  value = local.name
}

output "default_tags" {
  value = {
    "group" : local.name
    "app_name" : var.name_prefix
  }
}
