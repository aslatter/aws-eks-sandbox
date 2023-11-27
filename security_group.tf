
// https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html

// TODO - check to see if this keeps the default "allow all" egress
// rules.

resource "aws_security_group" "eks_cluster" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name : "eks-cluster"
  }

  lifecycle {
    create_before_destroy = true
  }
}

// allow ingress from nodes
resource "aws_security_group_rule" "eks_cluster" {
  security_group_id = aws_security_group.eks_cluster.id

  type                     = "ingress"
  source_security_group_id = aws_security_group.eks_nodes.id
  protocol                 = "tcp"
  from_port                = "443"
  to_port                  = "443"
}

resource "aws_security_group" "eks_nodes" {
  description = "Custom EKS node security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name : "eks-nodes"
    //"kubernetes.io/cluster/${cluster name}" = "owned"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "eks_nodes" {
  // the commnity eks module is a lot more restictive in
  // its 'nodes' security-group. here, we all all node->node
  // traffic.
  for_each = {
    "ingress_self" = {
      description = "node-to-node traffic"
      type        = "ingress"
      protocol    = "all"
      from_port   = 0
      to_port     = 0
      self        = true
    },
    "ingress_cluster_tls" = {
      description           = "control-plane to node TLS"
      type                  = "ingress"
      protocol              = "tcp"
      from_port             = 443
      to_port               = 443
      source_security_group = "cluster"
    },
    "ingress_cluster_kubelet" = {
      description           = "control plane to kubelet"
      type                  = "ingress"
      protocol              = "tcp"
      from_port             = 10250
      to_port               = 10250
      source_security_group = "cluster"
    }
  }

  security_group_id = aws_security_group.eks_nodes.id
  type              = each.value.type
  protocol          = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port

  description = lookup(each.value, "description", null)
  self        = lookup(each.value, "self", null)
  source_security_group_id = (try(each.value.source_security_group, null) == null
    ? null
    : each.value.source_security_group == "cluster" ? aws_security_group.eks_cluster.id
    : null
  )
}

