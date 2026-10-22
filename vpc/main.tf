terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
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
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "flow_log_retention_days" {
  description = "Number of days to retain VPC flow logs"
  type        = number
  default     = 90
}

# -----------------------------------------------------------------
# VPC
# -----------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "vpc-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  })
}

# -----------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "igw-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  })
}

# -----------------------------------------------------------------
# Public Subnets
# -----------------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "subnet-public-${count.index + 1}-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
    Tier = "public"
  })
}

# -----------------------------------------------------------------
# Private Subnets
# -----------------------------------------------------------------
resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "subnet-private-${count.index + 1}-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
    Tier = "private"
  })
}

# -----------------------------------------------------------------
# Elastic IPs for NAT Gateways
# -----------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "eip-nat-${count.index + 1}-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  })

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------
# NAT Gateways (one per AZ for HA)
# -----------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "nat-${count.index + 1}-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  })

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------
# Public Route Table
# -----------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "rtb-public-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
    Tier = "public"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------
# Private Route Tables (one per AZ for HA)
# -----------------------------------------------------------------
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "rtb-private-${count.index + 1}-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
    Tier = "private"
  })
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# -----------------------------------------------------------------
# Security Group – Public / Web Tier (DMZ)
# -----------------------------------------------------------------
resource "aws_security_group" "public_web" {
  name        = "sg-public-web-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  description = "Security group for the public DMZ web tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTPS from the Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP from the Internet (redirect to HTTPS)"
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
    Name = "sg-public-web-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  })
}

# -----------------------------------------------------------------
# Security Group – Private / Application Tier
# -----------------------------------------------------------------
resource "aws_security_group" "private_app" {
  name        = "sg-private-app-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  description = "Security group for the private application tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow traffic from the public web tier"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.public_web.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "sg-private-app-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  })
}

# -----------------------------------------------------------------
# Security Group – Private / Data Tier
# -----------------------------------------------------------------
resource "aws_security_group" "private_data" {
  name        = "sg-private-data-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  description = "Security group for the private data tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow database traffic from the application tier"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.private_app.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "sg-private-data-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  })
}

# -----------------------------------------------------------------
# VPC Flow Logs – CloudWatch
# -----------------------------------------------------------------
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flow-logs/${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  retention_in_days = var.flow_log_retention_days

  tags = merge(local.common_tags, {
    Name = "lg-vpc-flow-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  })
}

resource "aws_iam_role" "vpc_flow_log" {
  name = "role-vpc-flow-log-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "role-vpc-flow-log-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  })
}

resource "aws_iam_role_policy" "vpc_flow_log" {
  name = "policy-vpc-flow-log-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  role = aws_iam_role.vpc_flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = merge(local.common_tags, {
    Name = "flow-log-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  })
}

# -----------------------------------------------------------------
# CloudWatch Alarms – NAT Gateway monitoring
# -----------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "nat_error_port_allocation" {
  count               = length(var.public_subnet_cidrs)
  alarm_name          = "alarm-nat-port-alloc-${count.index + 1}-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  alarm_description   = "NAT Gateway port allocation errors exceed threshold"
  namespace           = "AWS/NATGateway"
  metric_name         = "ErrorPortAllocation"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    NatGatewayId = aws_nat_gateway.main[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "alarm-nat-port-alloc-${count.index + 1}-${local.common_tags["Application"]}-${local.common_tags["Environment"]}"
  })
}

# -----------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = aws_route_table.private[*].id
}

output "sg_public_web_id" {
  description = "ID of the public web tier security group"
  value       = aws_security_group.public_web.id
}

output "sg_private_app_id" {
  description = "ID of the private application tier security group"
  value       = aws_security_group.private_app.id
}

output "sg_private_data_id" {
  description = "ID of the private data tier security group"
  value       = aws_security_group.private_data.id
}

output "vpc_flow_log_group_name" {
  description = "Name of the CloudWatch log group for VPC flow logs"
  value       = aws_cloudwatch_log_group.vpc_flow_logs.name
}
