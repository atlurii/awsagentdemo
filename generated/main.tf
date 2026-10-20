```hcl
# generated/main.tf
# Terraform configuration for EC2 instance with existing EBS volume association
# Tags: Environment=production, Application=web-portal, Owner=it-operations-team

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Provider
# ---------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
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
  }

  name_prefix = "${var.application_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Data sources – reference existing infrastructure
# ---------------------------------------------------------------------------
data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnet" "selected" {
  id = var.subnet_id
}

data "aws_ebs_volume" "existing" {
  most_recent = true

  filter {
    name   = "volume-id"
    values = [var.existing_ebs_volume_id]
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

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# IAM Role and Instance Profile
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ec2_role" {
  name               = "${local.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for ${local.name_prefix} EC2 instance"

  tags = {
    Name = "${local.name_prefix}-ec2-role"
  }
}

# Allow SSM Session Manager access (best practice: no SSH bastion needed)
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow CloudWatch Agent to publish metrics and logs
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_role.name

  tags = {
    Name = "${local.name_prefix}-ec2-profile"
  }
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

# Security group for the web-portal EC2 instance (DMZ web tier)
resource "aws_security_group" "web_portal" {
  name        = "${local.name_prefix}-web-portal-sg"
  description = "Security group for ${local.name_prefix} web portal EC2 instance (DMZ web tier)"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name = "${local.name_prefix}-web-portal-sg"
    Tier = "dmz-web-tier"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS inbound
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.web_portal.id
  description       = "Allow HTTPS inbound traffic"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowed_cidr_https

  tags = {
    Name = "${local.name_prefix}-allow-https"
  }
}

# HTTP inbound (redirect to HTTPS at application level)
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web_portal.id
  description       = "Allow HTTP inbound traffic (redirect to HTTPS)"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowed_cidr_http

  tags = {
    Name = "${local.name_prefix}-allow-http"
  }
}

# All egress traffic
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.web_portal.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${local.name_prefix}-allow-all-egress"
  }
}

# ---------------------------------------------------------------------------
# KMS key for EBS root volume encryption
# ---------------------------------------------------------------------------
resource "aws_kms_key" "ebs_encryption" {
  description             = "KMS key for ${local.name_prefix} EBS root volume encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${local.name_prefix}-ebs-kms-key"
  }
}

resource "aws_kms_alias" "ebs_encryption" {
  name          = "alias/${local.name_prefix}-ebs-key"
  target_key_id = aws_kms_key.ebs_encryption.key_id
}

# ---------------------------------------------------------------------------
# EC2 Instance
# ---------------------------------------------------------------------------
resource "aws_instance" "web_portal" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.selected.id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = var.key_name != "" ? var.key_name : null
  monitoring             = true  # Enable detailed CloudWatch monitoring
  ebs_optimized          = true