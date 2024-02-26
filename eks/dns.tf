
locals {
  dns_enabled = var.dns.parent_zone_id != null && var.dns.name != null
}

data "aws_route53_zone" "parent" {
  count   = local.dns_enabled ? 1 : 0
  zone_id = var.dns.parent_zone_id
}

locals {
  dns_info = local.dns_enabled ? { domain : "${var.dns.name}.${data.aws_route53_zone.parent[0].name}" } : {}
}

output "dns_info" {
  value = local.dns_info
}

resource "aws_route53_record" "api_v4_base" {
  count = local.dns_enabled ? 1 : 0

  zone_id = var.dns.parent_zone_id
  name    = "api.${var.dns.name}"
  type    = "A"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = true // ??
  }
}

resource "aws_route53_record" "api_v6_base" {
  count = local.dns_enabled ? 1 : 0

  zone_id = var.dns.parent_zone_id
  name    = "api.${var.dns.name}"
  type    = "AAAA"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = true // ??
  }
}

resource "aws_route53_record" "api_v4_wildcard" {
  count = local.dns_enabled ? 1 : 0

  zone_id = var.dns.parent_zone_id
  name    = "*.api.${var.dns.name}"
  type    = "A"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = true // ??
  }
}

resource "aws_route53_record" "api_v6_wildcard" {
  count = local.dns_enabled ? 1 : 0

  zone_id = var.dns.parent_zone_id
  name    = "*.api.${var.dns.name}"
  type    = "AAAA"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = true // ??
  }
}
