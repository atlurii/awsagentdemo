```hcl
# ./generated/ec2/main.tf

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Local values
# ---------------------------------------------------------------------------
locals {
  common_tags = {
    Environment         = "production"
    Application         = "web-portal"
    Owner               = "it-operations-team"
    CostCenter          = "IT-OPS-003"          # updated value
    Project             = "digital-transformation"
    ServiceLevel        = "critical"
    BackupRequired      = "true"
    MonitoringEnabled   = "true"
    PatchGroup          = "monthly"
    ComplianceRequired  = "sox-gdpr"
    DataClassification  = "confidential"
    BusinessUnit        = "healthcare-technology"
    MaintenanceWindow   = "sunday-02:00-06:00"
    DisasterRecovery    = "enabled"
    SecurityGroup       = "dmz-web-tier"
    AutoScaling         = "enabled"
    LogRetention        = "90-days"
    IncidentPriority    = "high"
    ServiceDesk         = "servicenow-integration"
    ChangeManagement    = "required"
  }
}

# ---------------------------------------------------------------------------
# Data sources – reference existing infrastructure
# ---------------------------------------------------------------------------
data "aws_vpc" "main" {
  tags = {
    Environment = local.common_tags["Environment"]
    Project     = local.common_tags["Project"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = {
    Tier = "public"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = {
    Tier = "private"
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

data "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "ec2-ssm-instance-profile"
}

data "aws_sns_topic" "alerts" {
  name = "infrastructure-alerts-${local.common_tags["Environment"]}"
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "dmz-web-tier-alb-${local.common_tags["Environment"]}"
  description = "ALB security group for ${local.common_tags["Application"]} – DMZ web tier"
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
    Name = "dmz-web-tier-alb-${local.common_tags["Environment"]}"
    Role = "alb"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "web" {
  name        = "dmz-web-tier-ec2-${local.common_tags["Environment"]}"
  description = "EC2 security group for ${local.common_tags["Application"]} – DMZ web tier"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTPS from ALB only"
    from_port       = 8443
    to_port         = 8443
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
    Name = "dmz-web-tier-ec2-${local.common_tags["Environment"]}"
    Role = "web-server"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# KMS key for EBS encryption
# ---------------------------------------------------------------------------
resource "aws_kms_key" "ebs" {
  description             = "KMS key for EBS encryption – ${local.common_tags["Application"]}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name    = "${local.common_tags["Application"]}-ebs-kms-${local.common_tags["Environment"]}"
    Purpose = "ebs-encryption"
  })
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${local.common_tags["Application"]}-ebs-${local.common_tags["Environment"]}"
  target_key_id = aws_kms_key.ebs.key_id
}

# ---------------------------------------------------------------------------
# Launch Template
# ---------------------------------------------------------------------------
resource "aws_launch_template" "web" {
  name_prefix   = "${local.common_tags["Application"]}-lt-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.medium"

  iam_instance_profile {
    name = data.aws_iam_instance_profile.ec2_ssm_profile.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.web.id]
    delete_on_termination       = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 50
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.ebs.arn
      delete_on_termination = true
      throughput            = 125
      iops                  = 3000
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # IMDSv2 enforced
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = true   # detailed CloudWatch monitoring
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail
    yum update -y
    yum install -y amazon-cloudwatch-agent amazon-