
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

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  ingress {
    protocol    = -1
    self        = true
    from_port   = 0
    to_port     = 0
    cidr_blocks = var.public_access_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name : "default"
  }
}

// I don't fully understand how ACLs would be useful,
// as they are not stateful.

// public subnet
//
// the public subet will hold any load-balencers for ingress.
resource "aws_subnet" "public" {
  count = var.node_az_count

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = var.vpc_public_subnets[count.index]

  tags = {
    Name : "subnet-public-${local.azs[count.index]}"

    "kubernetes.io/cluster/${local.cluster_name}" : "shared"
    "kubernetes.io/role/elb" : 1
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
// the pirvate subnet will hold our k8s nodes.
// direct internet access is not allowed, however we do
// have a route to a NAT-gateway for internet egress.
//
// we have as many subnets as we wish to have AZs for
// out k8s nodes. We also provision a separate NAT
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
