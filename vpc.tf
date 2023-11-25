
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
}

// I don't fully understand how ACLs would be useful,
// as they are not stateful.

// public subnet

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

resource "aws_subnet" "private" {
  count = var.node_az_count

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = var.vpc_private_subnets[count.index]

  tags = {
    Name : "subnet-private-${local.azs[count.index]}"
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
  // creating one per AZ
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
