
// https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html
// https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html

// SG we apply to EKS-managed control-plane NICs it installs
// in our subnets.
resource "aws_security_group" "eks_cluster" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name : "sg-eks-cluster"
  }

  lifecycle {
    create_before_destroy = true
  }
}

// SG we apply to k8s nodes themselves.
resource "aws_security_group" "eks_nodes" {
  description = "Custom EKS node security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name : "sg-eks-nodes"
  }

  lifecycle {
    create_before_destroy = true
  }
}

// SG we apply to front-end load-balancer
resource "aws_security_group" "nlb" {
  description = "Network load balancer security group"

  vpc_id = aws_vpc.main.id

  tags = {
    Name : "sg-nlb"
  }

  lifecycle {
    create_before_destroy = true
  }
}

// allow ingress into control-plane from nodes
resource "aws_vpc_security_group_ingress_rule" "eks_cluster" {
  security_group_id = aws_security_group.eks_cluster.id

  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "tcp"
  from_port                    = "443"
  to_port                      = "443"
}

// node-SG rules.
locals {
  node_sg_rules = {
    "ingress_self" = {
      description               = "node-to-node traffic"
      type                      = "ingress"
      protocol                  = "all"
      referenced_security_group = "self"
    },
    "ingress_cluster_tls" = {
      description               = "control-plane to node TLS"
      type                      = "ingress"
      protocol                  = "tcp"
      from_port                 = 443
      to_port                   = 443
      referenced_security_group = "cluster"
    },
    "ingress_cluster_kubelet" = {
      description               = "control plane to kubelet"
      type                      = "ingress"
      protocol                  = "tcp"
      from_port                 = 10250
      to_port                   = 10250
      referenced_security_group = "cluster"
    },
    ingress_cluster_metrics = {
      description               = "allow reaching metrics endpoint from control plane"
      type                      = "ingress"
      protocol                  = "tcp"
      from_port                 = 4443
      to_port                   = 4443
      referenced_security_group = "cluster"
    }
    ingress_lb_controller_webhook = {
      description               = "allow reaching lb controller webhook from control plane"
      type                      = "ingress"
      protocol                  = "tcp"
      from_port                 = 9443
      to_port                   = 9443
      referenced_security_group = "cluster"
    }
    ingress_nlb = {
      // because we are registering the pod-ips directly with
      // the nlb, and the pods can choose to serve from an arbitrary
      // port, there really aren't restrictions we can reasonably
      // apply here. This could be restricted to the container-ports
      // of our ingress controller (but nothing stops other pods from
      // using those ports).
      description               = "allow all from nlb"
      type                      = "ingress"
      protocol                  = "-1"
      referenced_security_group = "nlb"
    }
    "egress_ipv4" = {
      description = "allow egress"
      type        = "egress"
      protocol    = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
    "egress_ipv6" = {
      description = "allow egress"
      type        = "egress"
      protocol    = "-1"
      cidr_ipv6   = "::/0"
    }
  }
}

// apply the above node rules
resource "aws_vpc_security_group_ingress_rule" "eks_nodes" {
  // the commnity eks module is a lot more restictive in
  // its 'nodes' security-group. here, we allow all node->node
  // traffic.
  for_each = { for k, v in local.node_sg_rules :
    k => v
    if v.type == "ingress"
  }

  security_group_id = aws_security_group.eks_nodes.id
  ip_protocol       = each.value.protocol

  from_port = lookup(each.value, "from_port", null)
  to_port   = lookup(each.value, "to_port", null)

  description = lookup(each.value, "description", null)
  cidr_ipv4   = lookup(each.value, "cidr_ipv4", null)
  cidr_ipv6   = lookup(each.value, "cidr_ipv6", null)

  referenced_security_group_id = (try(each.value.referenced_security_group, null) == null
    ? null
    : each.value.referenced_security_group == "self" ? aws_security_group.eks_nodes.id
    : each.value.referenced_security_group == "cluster" ? aws_security_group.eks_cluster.id
    : each.value.referenced_security_group == "nlb" ? aws_security_group.nlb.id
    : null
  )
}

// apply the above node rules
resource "aws_vpc_security_group_egress_rule" "eks_nodes" {
  // the commnity eks module is a lot more restictive in
  // its 'nodes' security-group. here, we allow all node->node
  // traffic.
  for_each = { for k, v in local.node_sg_rules :
    k => v
    if v.type == "egress"
  }

  security_group_id = aws_security_group.eks_nodes.id
  ip_protocol       = each.value.protocol

  from_port = lookup(each.value, "from_port", null)
  to_port   = lookup(each.value, "to_port", null)

  description = lookup(each.value, "description", null)
  cidr_ipv4   = lookup(each.value, "cidr_ipv4", null)
  cidr_ipv6   = lookup(each.value, "cidr_ipv6", null)
}

resource "aws_vpc_security_group_egress_rule" "nlb_nodes" {
  security_group_id            = aws_security_group.nlb.id
  ip_protocol                  = "all"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

// nlb-ingress rules. we wish to allow 80 and 443, udp and tcp, ipv4
// and ipv6. NLBs with an "ip" target-type don't actually support UDP,
// but we can dream.
//
// I couldn't think of a better way to do this than brute-force, so
// it's a bit tedious.

resource "aws_vpc_security_group_ingress_rule" "nlb_https_ipv4_tcp" {
  count = length(var.public_access_cidrs)

  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.public_access_cidrs[count.index]
}

resource "aws_vpc_security_group_ingress_rule" "nlb_https_ipv4_udp" {
  count = length(var.public_access_cidrs)

  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "udp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.public_access_cidrs[count.index]
}

resource "aws_vpc_security_group_ingress_rule" "nlb_https_ipv6_tcp" {
  count = length(var.public_access_cidrs_ipv6)

  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = var.public_access_cidrs_ipv6[count.index]
}

resource "aws_vpc_security_group_ingress_rule" "nlb_https_ipv6_udp" {
  count = length(var.public_access_cidrs_ipv6)

  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "udp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = var.public_access_cidrs_ipv6[count.index]
}

resource "aws_vpc_security_group_ingress_rule" "nlb_http_ipv4_tcp" {
  count = length(var.public_access_cidrs)

  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.public_access_cidrs[count.index]
}

resource "aws_vpc_security_group_ingress_rule" "nlb_http_ipv4_udp" {
  count = length(var.public_access_cidrs)

  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "udp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.public_access_cidrs[count.index]
}

resource "aws_vpc_security_group_ingress_rule" "nlb_http_ipv6_tcp" {
  count = length(var.public_access_cidrs_ipv6)

  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv6         = var.public_access_cidrs_ipv6[count.index]
}

resource "aws_vpc_security_group_ingress_rule" "nlb_http_ipv6_udp" {
  count = length(var.public_access_cidrs_ipv6)

  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "udp"
  from_port         = 80
  to_port           = 80
  cidr_ipv6         = var.public_access_cidrs_ipv6[count.index]
}
