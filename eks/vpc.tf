
// base VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block

  // https://docs.aws.amazon.com/vpc/latest/userguide/vpc-dns.html
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "vpc"
  }
}

// the default security group for a VPC is the security group
// resources end up in if we don't specify any other security
// group.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  ingress {
    protocol    = "all"
    self        = true
    from_port   = 0
    to_port     = 0
    cidr_blocks = var.public_access_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "all"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name : "sg-default"
  }
}

// we could apply ACLs to our subnets here, but they seem to
// be pretty limitted because they are not stateful.
//
// https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html

// Public Subnet
//
// The public subets will hold any load-balancers for ingress.
// We create one public subnet per AZ we are creating nodes in.
resource "aws_subnet" "public" {
  count = var.node_az_count

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = var.vpc_public_subnets[count.index]

  tags = {
    Name : "subnet-public-${local.azs[count.index]}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name : "rtb-public"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public[count.index].id
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
  // todo - community module includes a 5m timeout
}

// private subnet
//
// the private subnet will hold our k8s nodes.
// direct internet access is not allowed, however we do
// have a route to a NAT-gateway for internet egress.
//
// we have as many subnets as we wish to have AZs for
// our k8s nodes. We also provision a separate NAT
// gateway per AZ.
resource "aws_subnet" "private" {
  count = var.node_az_count

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = var.vpc_private_subnets[count.index]

  tags = {
    Name : "subnet-private-${local.azs[count.index]}"

    "kubernetes.io/cluster/${local.cluster_name}" : "shared"
    "kubernetes.io/role/internal-elb" : 1
  }
}

resource "aws_route_table" "private" {
  count = var.node_az_count

  vpc_id = aws_vpc.main.id

  tags = {
    Name : "rtb-private-${local.azs[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  route_table_id = aws_route_table.private[count.index].id
  subnet_id      = aws_subnet.private[count.index].id
}

// intra subnet (private, with no egress)
//
// the intra subnet is similar to the private subnet,
// except there is no internet egress route. We will
// tell EKS to install its control-plan NICs onto these
// subnets.
//
// We need as many subnets as we wish to have control-plane
// availability-zones (minimum of two).
resource "aws_subnet" "intra" {
  count = var.cluster_az_count

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = var.vpc_intra_subnets[count.index]

  tags = {
    Name : "subnet-intra-${local.azs[count.index]}"
  }
}

resource "aws_route_table" "intra" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name : "rtb-intra"
  }
}

resource "aws_route_table_association" "intra" {
  count          = length(aws_subnet.intra)
  route_table_id = aws_route_table.intra.id
  subnet_id      = aws_subnet.intra[count.index].id
}

// Consider ACL restricting traffic to private subnets?

// internet gateway

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name : "igw"
  }
}

// nat gateway

resource "aws_eip" "nat" {
  // creating one per node-AZ
  count  = var.node_az_count
  domain = "vpc"

  tags = {
    Name : "eip-nat-${local.azs[count.index]}"
  }

  // not sure why community module does this?
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = var.node_az_count

  // we assign IPv4 addresses to the ngw per AZ.
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name : "nat-gateway-${local.azs[count.index]}"
  }
}

// add route to each of our private-subnet route-tables for internet
// egress.
resource "aws_route" "private_nat_gateway" {
  count = var.node_az_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id

  // again the community module use a 5m create-timeout here?
}

// incoming NLB

resource "aws_eip" "nlb" {
  // creating one per node-AZ
  count  = var.node_az_count
  domain = "vpc"

  tags = {
    Name : "eip-nlb-${local.azs[count.index]}"
  }
}

resource "aws_lb" "nlb" {
  name_prefix        = "eks"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [aws_security_group.nlb.id]

  // we assign IPv4 addresses to the lb per AZ.
  dynamic "subnet_mapping" {
    for_each = range(var.node_az_count)
    content {
      subnet_id     = aws_subnet.public[subnet_mapping.value].id
      allocation_id = aws_eip.nlb[subnet_mapping.value].allocation_id
    }
  }

  tags = {
    Name : "nlb"
  }
}

resource "aws_lb_listener" "nlb_http" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_http.arn
  }

  tags = {
    Name : "nlb-listener-http"
  }
}

resource "aws_lb_target_group" "nlb_http" {
  name_prefix = "http-"
  target_type = "ip"
  protocol    = "TCP"
  port        = "80" // doesn't matter, as the targets will override this
  vpc_id      = aws_vpc.main.id
  // preserve client ip?

  health_check {
    // leave 'port' unspecified to default to the traffic-port
    protocol            = "TCP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 10 // seconds
    interval            = 10 // seconds
  }

  tags = {
    Name : "nlb-tg-http"
  }

  lifecycle {
    // we can't delete a target-group if its in-use by the
    // listener default-action.
    create_before_destroy = true
  }
}

//
// S3 gateway endpoint
//

// We're not directly using S3, but when our nodes
// pull images from ECR that uses S3. Adding the
// endpoint should save on NAT Gateway $$$.

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.s3"
}

resource "aws_vpc_endpoint_route_table_association" "s3" {
  for_each = merge(
    {
      public : aws_route_table.public.id
    },
    { for k, v in aws_route_table.private :
      "private-${k}" => v.id
    },
    {
      intra : aws_route_table.intra.id
    },
  )

  vpc_endpoint_id = aws_vpc_endpoint.s3.id
  route_table_id  = each.value

  depends_on = [
    // not a real dependency, but I want the resource
    // group created early in the deployment.
    aws_resourcegroups_group.group
  ]
}

locals {
  public_ips = aws_eip.nat[*].public_ip
}
