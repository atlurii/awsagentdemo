terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

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
  }
}

# ─── VPC ────────────────────────────────────────────────────────────────────

resource "aws_vpc" "web_portal_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "web-portal-production-vpc"
  })
}

# ─── INTERNET GATEWAY ───────────────────────────────────────────────────────

resource "aws_internet_gateway" "web_portal_igw" {
  vpc_id = aws_vpc.web_portal_vpc.id

  tags = merge(local.common_tags, {
    Name = "web-portal-production-igw"
  })
}

# ─── PUBLIC SUBNETS ─────────────────────────────────────────────────────────

resource "aws_subnet" "web_portal_public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.web_portal_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "web-portal-public-subnet-${count.index + 1}"
    Tier = "public"
  })
}

# ─── PRIVATE SUBNETS ────────────────────────────────────────────────────────

resource "aws_subnet" "web_portal_private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.web_portal_vpc.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "web-portal-private-subnet-${count.index + 1}"
    Tier = "private"
  })
}

# ─── ELASTIC IPs FOR NAT GATEWAYS ───────────────────────────────────────────

resource "aws_eip" "web_portal_nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"

  depends_on = [aws_internet_gateway.web_portal_igw]

  tags = merge(local.common_tags, {
    Name = "web-portal-nat-eip-${count.index + 1}"
  })
}

# ─── NAT GATEWAYS ───────────────────────────────────────────────────────────

resource "aws_nat_gateway" "web_portal_nat" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.web_portal_nat[count.index].id
  subnet_id     = aws_subnet.web_portal_public[count.index].id

  depends_on = [aws_internet_gateway.web_portal_igw]

  tags = merge(local.common_tags, {
    Name = "web-portal-nat-gateway-${count.index + 1}"
  })
}

# ─── PUBLIC ROUTE TABLE ─────────────────────────────────────────────────────

resource "aws_route_table" "web_portal_public" {
  vpc_id = aws_vpc.web_portal_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.web_portal_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-public-rt"
    Tier = "public"
  })
}

resource "aws_route_table_association" "web_portal_public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.web_portal_public[count.index].id
  route_table_id = aws_route_table.web_portal_public.id
}

# ─── PRIVATE ROUTE TABLES ───────────────────────────────────────────────────

resource "aws_route_table" "web_portal_private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.web_portal_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.web_portal_nat[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-private-rt-${count.index + 1}"
    Tier = "private"
  })
}

resource "aws_route_table_association" "web_portal_private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.web_portal_private[count.index].id
  route_table_id = aws_route_table.web_portal_private[count.index].id
}

# ─── SECURITY GROUPS ────────────────────────────────────────────────────────

resource "aws_security_group" "web_portal_public_sg" {
  name        = "web-portal-public-sg"
  description = "Security group for public-facing web portal resources in the DMZ web tier"
  vpc_id      = aws_vpc.web_portal_vpc.id

  ingress {
    description = "Allow HTTPS inbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP inbound for redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-public-sg"
  })
}

resource "aws_security_group" "web_portal_private_sg" {
  name        = "web-portal-private-sg"
  description = "Security group for private web portal resources"
  vpc_id      = aws_vpc.web_portal_vpc.id

  ingress {
    description     = "Allow traffic from public tier"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web_portal_public_sg.id]
  }

  ingress {
    description = "Allow internal VPC traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-private-sg"
  })
}

# ─── VPC FLOW LOGS ──────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "web_portal_vpc_flow_logs" {
  name              = "/aws/vpc/web-portal-production-flow-logs"
  retention_in_days = 90

  tags = merge(local.common_tags, {
    Name = "web-portal-vpc-flow-logs"
  })
}

resource "aws_iam_role" "web_portal_vpc_flow_logs_role" {
  name = "web-portal-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "web-portal-vpc-flow-logs-role"
  })
}

resource "aws_iam_role_policy" "web_portal_vpc_flow_logs_policy" {
  name = "web-portal-vpc-flow-logs-policy"
  role = aws_iam_role.web_portal_vpc_flow_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "web_portal_vpc_flow_log" {
  iam_role_arn    = aws_iam_role.web_portal_vpc_flow_logs_role.arn
  log_destination = aws_cloudwatch_log_group.web_portal_vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.web_portal_vpc.id

  tags = merge(local.common_tags, {
    Name = "web-portal-vpc-flow-log"
  })
}

# ─── CLOUDWATCH ALARMS ──────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "web_portal_nat_error_alarm" {
  count               = length(var.public_subnet_cidrs)
  alarm_name          = "web-portal-nat-gateway-error-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorPortAllocation"
  namespace           = "AWS/NATGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "NAT Gateway port allocation errors detected for web-portal production environment"
  treat_missing_data  = "notBreaching"

  dimensions = {
    NatGatewayId = aws_nat_gateway.web_portal_nat[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-nat-gateway-error-alarm-${count.index + 1}"
  })
}

# ─── OUTPUTS ────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "ID of the web portal VPC"
  value       = aws_vpc.web_portal_vpc.id
}

output "vpc_cidr" {
  description = "CIDR block of the web portal VPC"
  value       = aws_vpc.web_portal_vpc.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.web_portal_public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.web_portal_private[*].id
}

output "public_security_group_id" {
  description = "ID of the public-facing security group"
  value       = aws_security_group.web_portal_public_sg.id
}

output "private_security_group_id" {
  description = "ID of the private security group"
  value       = aws_security_group.web_portal_private_sg.id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways"
  value       = aws_nat_gateway.web_portal_nat[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.web_portal_igw.id
}
