
output "info" {
  value = {
    resourceGroup = {
      name = aws_resourcegroups_group.group.name
      id   = aws_resourcegroups_group.group.arn
    }
    region = var.region
  }
}