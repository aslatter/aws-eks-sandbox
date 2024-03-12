
locals {
  dns_enabled = var.dns.zone_name != null
}

resource "aws_route53_zone" "main" {
  count = local.dns_enabled ? 1 : 0
  name  = var.dns.zone_name
}


locals {
  dns_info = (local.dns_enabled ?
    {
      zone_id      = aws_route53_zone.main[0].zone_id
      domain       = aws_route53_zone.main[0].name
      name_servers = aws_route53_zone.main[0].name_servers
  } : null)
}

output "dns_info" {
  value = local.dns_info
}

resource "aws_route53_record" "api_v4_base" {
  count = local.dns_enabled ? 1 : 0

  zone_id = local.dns_info.zone_id
  name    = "api.${var.dns.zone_name}"
  type    = "A"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = true // ??
  }
}

resource "aws_route53_record" "api_v6_base" {
  count = local.dns_enabled ? 1 : 0

  zone_id = local.dns_info.zone_id
  name    = "api.${var.dns.zone_name}"
  type    = "AAAA"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = true // ??
  }
}

resource "aws_route53_record" "api_v4_wildcard" {
  count = local.dns_enabled ? 1 : 0

  zone_id = local.dns_info.zone_id
  name    = "*.api.${var.dns.zone_name}"
  type    = "A"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = true // ??
  }
}

resource "aws_route53_record" "api_v6_wildcard" {
  count = local.dns_enabled ? 1 : 0

  zone_id = local.dns_info.zone_id
  name    = "*.api.${var.dns.zone_name}"
  type    = "AAAA"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = true // ??
  }
}
