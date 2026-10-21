```hcl
# generated/main.tf
# Auto-generated Terraform configuration
# Tags: Environment=production, Application=web-portal

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ==============================================================================
# Local Values
# ==============================================================================

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
    GeneratedAt        = "generated/main.tf"
  }

  name_prefix = "web-portal-prod"
  app_port    = 443
  http_port   = 80
}

# ==============================================================================
# Data Sources — Reference Existing Infrastructure
# ==============================================================================

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "main" {
  tags = {
    Environment = "production"
    Project     = "digital-transformation"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = {
    Tier        = "public"
    Environment = "production"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = {
    Tier        = "private"
    Environment = "production"
  }
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_acm_certificate" "web_portal" {
  domain      = "web-portal.example.com"
  statuses    = ["ISSUED"]
  most_recent = true
}

data "aws_route53_zone" "primary" {
  name         = "example.com."
  private_zone = false
}

data "aws_sns_topic" "alerts" {
  name = "production-critical-alerts"
}

data "aws_kms_key" "main" {
  key_id = "alias/production-main-key"
}

# ==============================================================================
# Security Groups
# ==============================================================================

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for ALB - DMZ web tier - ${local.name_prefix}"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP redirect from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
    Tier = "dmz-web-tier"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "web" {
  name        = "${local.name_prefix}-web-sg"
  description = "Security group for web tier EC2 instances - ${local.name_prefix}"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "HTTPS from ALB only"
    from_port       = local.app_port
    to_port         = local.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTP from ALB only"
    from_port       = local.http_port
    to_port         = local.http_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web-sg"
    Tier = "web"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Security group for RDS instances - ${local.name_prefix}"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from web tier only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
    Tier = "database"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ==============================================================================
# IAM Role for EC2 Instances
# ==============================================================================

resource "aws_iam_role" "web_instance" {
  name        = "${local.name_prefix}-instance-role"
  description = "IAM role for web portal EC2 instances"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-instance-role"
  })
}

resource "aws_iam_role_policy_attachment" "ss