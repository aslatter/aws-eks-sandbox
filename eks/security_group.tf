
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

// allow ingress from nodes
resource "aws_security_group_rule" "eks_cluster" {
  security_group_id = aws_security_group.eks_cluster.id

  type                     = "ingress"
  source_security_group_id = aws_security_group.eks_nodes.id
  protocol                 = "tcp"
  from_port                = "443"
  to_port                  = "443"
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

resource "aws_security_group_rule" "eks_nodes" {
  for_each = {
  // the commnity eks module is a lot more restictive in
  // what node-to-node traffic it allows. here, we allow all node->node
  // traffic.
    "ingress_self" = {
      description = "node-to-node traffic"
      type        = "ingress"
      protocol    = "all"
      from_port   = 0
      to_port     = 0
      self        = true
    },
    // the community eks module is a lot more restrictive on
    // what communication it allows from the EKS control-plane
    // to the nodes. Debugging which ports to open up is a challenge,
    // however.
    control_plane = {
      desciption            = "allow all from control plane"
      type                  = "ingress"
      protocol              = "-1"
      to_port               = 0
      from_port             = 0
      source_security_group = "cluster"
    }
    "egress" = {
      description      = "allow egress"
      type             = "egress"
      protocol         = "-1"
      to_port          = 0
      from_port        = 0
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  security_group_id = aws_security_group.eks_nodes.id
  type              = each.value.type
  protocol          = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port

  description      = lookup(each.value, "description", null)
  self             = lookup(each.value, "self", null)
  cidr_blocks      = lookup(each.value, "cidr_blocks", null)
  ipv6_cidr_blocks = lookup(each.value, "ipv6_cidr_blocks", null)

  source_security_group_id = (try(each.value.source_security_group, null) == null
    ? null
    : each.value.source_security_group == "cluster" ? aws_security_group.eks_cluster.id
    : null
  )
}
