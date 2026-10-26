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
  description = "Availability zones for subnet deployment"
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

# VPC
resource "aws_vpc" "web_portal_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "web-portal-production-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "web_portal_igw" {
  vpc_id = aws_vpc.web_portal_vpc.id

  tags = merge(local.common_tags, {
    Name = "web-portal-production-igw"
  })
}

# Public Subnets
resource "aws_subnet" "web_portal_public_subnet" {
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

# Private Subnets
resource "aws_subnet" "web_portal_private_subnet" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.web_portal_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name = "web-portal-private-subnet-${count.index + 1}"
    Tier = "private"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "web_portal_nat_eip" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "web-portal-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.web_portal_igw]
}

# NAT Gateways (one per public subnet for HA)
resource "aws_nat_gateway" "web_portal_nat_gateway" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.web_portal_nat_eip[count.index].id
  subnet_id     = aws_subnet.web_portal_public_subnet[count.index].id

  tags = merge(local.common_tags, {
    Name = "web-portal-nat-gateway-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.web_portal_igw]
}

# Public Route Table
resource "aws_route_table" "web_portal_public_rt" {
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

# Private Route Tables (one per AZ)
resource "aws_route_table" "web_portal_private_rt" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.web_portal_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.web_portal_nat_gateway[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-private-rt-${count.index + 1}"
    Tier = "private"
  })
}

# Public Route Table Associations
resource "aws_route_table_association" "web_portal_public_rta" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.web_portal_public_subnet[count.index].id
  route_table_id = aws_route_table.web_portal_public_rt.id
}

# Private Route Table Associations
resource "aws_route_table_association" "web_portal_private_rta" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.web_portal_private_subnet[count.index].id
  route_table_id = aws_route_table.web_portal_private_rt[count.index].id
}

# Security Group: Public Web Tier
resource "aws_security_group" "web_portal_public_sg" {
  name        = "web-portal-public-sg"
  description = "Security group for public-facing web tier resources"
  vpc_id      = aws_vpc.web_portal_vpc.id

  ingress {
    description = "Allow HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP from internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-public-sg"
    Tier = "public"
  })
}

# Security Group: Private App Tier
resource "aws_security_group" "web_portal_private_app_sg" {
  name        = "web-portal-private-app-sg"
  description = "Security group for private application tier resources"
  vpc_id      = aws_vpc.web_portal_vpc.id

  ingress {
    description     = "Allow traffic from public web tier"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web_portal_public_sg.id]
  }

  ingress {
    description     = "Allow HTTPS from public web tier"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.web_portal_public_sg.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-private-app-sg"
    Tier = "private"
  })
}

# Security Group: Private Data Tier
resource "aws_security_group" "web_portal_private_data_sg" {
  name        = "web-portal-private-data-sg"
  description = "Security group for private data tier resources (RDS, ElastiCache)"
  vpc_id      = aws_vpc.web_portal_vpc.id

  ingress {
    description     = "Allow database traffic from app tier"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_portal_private_app_sg.id]
  }

  ingress {
    description     = "Allow MySQL/Aurora from app tier"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_portal_private_app_sg.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-private-data-sg"
    Tier = "data"
  })
}

# VPC Flow Logs IAM Role
resource "aws_iam_role" "web_portal_flow_logs_role" {
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

# VPC Flow Logs IAM Policy
resource "aws_iam_role_policy" "web_portal_flow_logs_policy" {
  name = "web-portal-vpc-flow-logs-policy"
  role = aws_iam_role.web_portal_flow_logs_role.id

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

# CloudWatch Log Group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "web_portal_vpc_flow_logs" {
  name              = "/aws/vpc/web-portal-production-flow-logs"
  retention_in_days = 90

  tags = merge(local.common_tags, {
    Name = "web-portal-vpc-flow-logs"
  })
}

# VPC Flow Logs
resource "aws_flow_log" "web_portal_vpc_flow_log" {
  vpc_id          = aws_vpc.web_portal_vpc.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.web_portal_flow_logs_role.arn
  log_destination = aws_cloudwatch_log_group.web_portal_vpc_flow_logs.arn

  tags = merge(local.common_tags, {
    Name = "web-portal-production-flow-log"
  })
}

# CloudWatch Metric Alarm: NAT Gateway Error Port Allocation
resource "aws_cloudwatch_metric_alarm" "web_portal_nat_gateway_error" {
  count               = length(var.public_subnet_cidrs)
  alarm_name          = "web-portal-nat-gateway-error-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorPortAllocation"
  namespace           = "AWS/NATGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "NAT Gateway port allocation errors detected for web-portal production VPC"
  treat_missing_data  = "notBreaching"

  dimensions = {
    NatGatewayId = aws_nat_gateway.web_portal_nat_gateway[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-nat-gateway-error-alarm-${count.index + 1}"
  })
}

# CloudWatch Metric Alarm: VPC Flow Log Delivery Errors
resource "aws_cloudwatch_metric_alarm" "web_portal_flow_log_delivery_error" {
  alarm_name          = "web-portal-flow-log-delivery-error"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DeliveryThrottling"
  namespace           = "AWS/Logs"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "VPC Flow Log delivery errors detected for web-portal production"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LogGroupName = aws_cloudwatch_log_group.web_portal_vpc_flow_logs.name
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-flow-log-delivery-error-alarm"
  })
}

# Outputs
output "vpc_id" {
  description = "ID of the web-portal production VPC"
  value       = aws_vpc.web_portal_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the web-portal production VPC"
  value       = aws_vpc.web_portal_vpc.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.web_portal_public_subnet[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.web_portal_private_subnet[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.web_portal_igw.id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = aws_nat_gateway.web_portal_nat_gateway[*].id
}

output "public_security_group_id" {
  description = "ID of the public web tier security group"
  value       = aws_security_group.web_portal_public_sg.id
}

output "private_app_security_group_id" {
  description = "ID of the private application tier security group"
  value       = aws_security_group.web_portal_private_app_sg.id
}

output "private_data_security_group_id" {
  description = "ID of the private data tier security group"
  value       = aws_security_group.web_portal_private_data_sg.id
}

output "vpc_flow_log_group_name" {
  description = "Name of the CloudWatch Log Group for VPC Flow Logs"
  value       = aws_cloudwatch_log_group.web_portal_vpc_flow_logs.name
}
