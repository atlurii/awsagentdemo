```hcl
# vpc/main.tf
# VPC with Public and Private Subnets
# Environment: production | Application: web-portal
# Compliance: SOX-GDPR | Classification: confidential

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Local values
# ---------------------------------------------------------------------------
locals {
  common_tags = {
    Environment        = "production"
    Application        = "web-portal"
    Owner              = "it-operations-team"
    CostCenter         = "IT-OPS-001"
    Project            = "digital-transformation"
    ServiceLevel       = "critical"
    BackupRequired     = "true"
    MonitoringEnabled  = "true"
    PatchGroup         = "monthly"
    ComplianceRequired = "sox-gdpr"
    DataClassification = "confidential"
    BusinessUnit       = "healthcare-technology"
    MaintenanceWindow  = "sunday-02:00-06:00"
    DisasterRecovery   = "enabled"
    SecurityGroup      = "dmz-web-tier"
    AutoScaling        = "enabled"
    LogRetention       = "90-days"
    IncidentPriority   = "high"
    ServiceDesk        = "servicenow-integration"
    ChangeManagement   = "required"
    ManagedBy          = "terraform"
  }

  vpc_cidr             = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  # Use only the first 3 AZs (or fewer if region has less)
  az_count = min(3, length(local.azs))
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "vpc-web-portal-production"
  })
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "igw-web-portal-production"
  })
}

# ---------------------------------------------------------------------------
# Public Subnets
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                     = "subnet-public-${local.azs[count.index]}-web-portal-production"
    SubnetType               = "public"
    AvailabilityZone         = local.azs[count.index]
    "kubernetes.io/role/elb" = "1" # reserved for future EKS use
  })
}

# ---------------------------------------------------------------------------
# Private Subnets
# ---------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.private_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name                              = "subnet-private-${local.azs[count.index]}-web-portal-production"
    SubnetType                        = "private"
    AvailabilityZone                  = local.azs[count.index]
    "kubernetes.io/role/internal-elb" = "1" # reserved for future EKS use
  })
}

# ---------------------------------------------------------------------------
# Elastic IPs for NAT Gateways (one per AZ for HA)
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = local.az_count
  domain = "vpc"

  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name             = "eip-nat-${local.azs[count.index]}-web-portal-production"
    AvailabilityZone = local.azs[count.index]
  })
}

# ---------------------------------------------------------------------------
# NAT Gateways (one per AZ for high availability)
# ---------------------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  count = local.az_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name             = "nat-gw-${local.azs[count.index]}-web-portal-production"
    AvailabilityZone = local.azs[count.index]
  })
}

# ---------------------------------------------------------------------------
# Route Tables – Public
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name       = "rtb-public-web-portal-production"
    SubnetType = "public"
  })
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Route Tables – Private (one per AZ for AZ-local NAT routing)
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  count  = local.az_count
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(local.common_tags, {
    Name             = "rtb-private-${local.azs[count.index]}-web-portal-production"
    SubnetType       = "private"
    AvailabilityZone = local.azs[count.index]
  })
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

# --- Public / DMZ Web Tier ---
resource "aws_security_group" "public_web" {
  name        = "sg-dmz-web-tier-public-web-portal-production"
  description = "DMZ web tier: allow HTTPS/HTTP from internet, restrict all else"
  vpc_id      = aws_vpc.main.