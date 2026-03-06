# terraform/vpc.tf

#######################
# VPC
#######################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "securebankapp-vpc" }
}

#######################
# Internet Gateway
#######################
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "securebankapp-igw" }
}

#######################
# Public Subnets
#######################
resource "aws_subnet" "public" {
  for_each = {
    "1a" = { cidr = "10.0.1.0/24", az = "us-east-1a" }
    "1b" = { cidr = "10.0.2.0/24", az = "us-east-1b" }
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true
  tags                    = { Name = "public-${each.key}" }
}

#######################
# Private Subnets (App Servers)
#######################
resource "aws_subnet" "private" {
  for_each = {
    "1a" = { cidr = "10.0.3.0/24", az = "us-east-1a" }
    "1b" = { cidr = "10.0.4.0/24", az = "us-east-1b" }
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags              = { Name = "private-${each.key}" }
}

#######################
# DB Subnets (No Internet)
#######################
resource "aws_subnet" "db" {
  for_each = {
    "1a" = { cidr = "10.0.5.0/24", az = "us-east-1a" }
    "1b" = { cidr = "10.0.6.0/24", az = "us-east-1b" }
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags              = { Name = "db-${each.key}" }
}

#######################
# NAT Gateways (one per AZ)
#######################
resource "aws_eip" "nat" {
  for_each = aws_subnet.public
  domain   = "vpc"
  tags     = { Name = "nat-eip-${each.key}" }
}

resource "aws_nat_gateway" "main" {
  for_each      = aws_subnet.public
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id
  tags          = { Name = "nat-${each.key}" }
  depends_on    = [aws_internet_gateway.main]
}

#######################
# Route Tables
#######################
# Public route table: Internet access
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "public-rt" }
}

# Private route tables: route to NAT gateways
resource "aws_route_table" "private" {
  for_each = aws_subnet.private
  vpc_id   = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[each.key].id
  }
  tags = { Name = "private-rt-${each.key}" }
}

# DB subnet route table: no default route (isolated)
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "db-rt" }
}

#######################
# Route Table Associations
#######################
# Public
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# DB
resource "aws_route_table_association" "db" {
  for_each       = aws_subnet.db
  subnet_id      = each.value.id
  route_table_id = aws_route_table.db.id
}