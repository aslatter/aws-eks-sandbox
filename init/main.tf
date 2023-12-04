
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

output "name" {
  value = "${var.name_prefix}-${random_string.suffix.result}"
}