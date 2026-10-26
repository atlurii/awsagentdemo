terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "ID of the existing VPC"
  type        = string
}

variable "subnet_id" {
  description = "ID of the existing subnet for the EC2 instance"
  type        = string
}

variable "ami_id" {
  description = "AMI ID to use for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of the existing EC2 key pair"
  type        = string
}

variable "existing_ebs_volume_id" {
  description = "ID of the existing EBS volume to attach"
  type        = string
}

variable "ebs_device_name" {
  description = "Device name for the EBS volume attachment"
  type        = string
  default     = "/dev/xvdf"
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH into the instance"
  type        = list(string)
  default     = []
}

variable "allowed_https_cidr_blocks" {
  description = "CIDR blocks allowed to reach HTTPS on the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_http_cidr_blocks" {
  description = "CIDR blocks allowed to reach HTTP on the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# Local values – centralised tag map
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# IAM role & instance profile – for SSM + CloudWatch agent
# -----------------------------------------------------------------------------

resource "aws_iam_role" "web_portal_ec2_role" {
  name = "web-portal-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "web-portal-ec2-role"
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.web_portal_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  role       = aws_iam_role.web_portal_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "web_portal_instance_profile" {
  name = "web-portal-instance-profile"
  role = aws_iam_role.web_portal_ec2_role.name

  tags = merge(local.common_tags, {
    Name = "web-portal-instance-profile"
  })
}

# -----------------------------------------------------------------------------
# Security group
# -----------------------------------------------------------------------------

resource "aws_security_group" "web_portal_public_sg" {
  name        = "web-portal-public-sg"
  description = "Security group for web-portal EC2 instance (DMZ web tier)"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from allowed CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_https_cidr_blocks
  }

  ingress {
    description = "HTTP from allowed CIDRs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidr_blocks
  }

  dynamic "ingress" {
    for_each = length(var.allowed_ssh_cidr_blocks) > 0 ? [1] : []
    content {
      description = "SSH from restricted CIDRs"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidr_blocks
    }
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

# -----------------------------------------------------------------------------
# EC2 instance
# -----------------------------------------------------------------------------

resource "aws_instance" "web_portal" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.web_portal_instance_profile.name
  vpc_security_group_ids = [aws_security_group.web_portal_public_sg.id]

  # Root volume – encrypted at rest
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true

    tags = merge(local.common_tags, {
      Name = "web-portal-root-volume"
    })
  }

  # Enable detailed (1-minute) CloudWatch monitoring
  monitoring = true

  # Prevent accidental termination in production
  disable_api_termination = true

  # Replace instance on type change instead of stop/start
  lifecycle {
    ignore_changes = [ami]
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail

    # Install CloudWatch agent
    yum install -y amazon-cloudwatch-agent || \
      apt-get install -y amazon-cloudwatch-agent

    # Start SSM agent (pre-installed on Amazon Linux 2/Ubuntu SSM AMIs)
    systemctl enable amazon-ssm-agent || true
    systemctl start  amazon-ssm-agent || true
  EOF
  )

  tags = merge(local.common_tags, {
    Name = "web-portal-ec2-instance"
  })
}

# -----------------------------------------------------------------------------
# Attach existing EBS volume
# -----------------------------------------------------------------------------

resource "aws_volume_attachment" "web_portal_ebs_attachment" {
  device_name  = var.ebs_device_name
  volume_id    = var.existing_ebs_volume_id
  instance_id  = aws_instance.web_portal.id
  force_detach = false
}

# -----------------------------------------------------------------------------
# CloudWatch alarms – basic instance monitoring
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "web_portal_cpu_high" {
  alarm_name          = "web-portal-cpu-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU utilization exceeded 80% for 3 consecutive minutes"
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = aws_instance.web_portal.id
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-cpu-utilization-high"
  })
}

resource "aws_cloudwatch_metric_alarm" "web_portal_status_check_failed" {
  alarm_name          = "web-portal-status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "EC2 status check failure detected"
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = aws_instance.web_portal.id
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-status-check-failed"
  })
}

resource "aws_cloudwatch_metric_alarm" "web_portal_disk_read_ops_high" {
  alarm_name          = "web-portal-disk-read-ops-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DiskReadOps"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 1000
  alarm_description   = "Disk read operations exceeded threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.web_portal.id
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-disk-read-ops-high"
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "ID of the web-portal EC2 instance"
  value       = aws_instance.web_portal.id
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.web_portal.private_ip
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance (if assigned)"
  value       = aws_instance.web_portal.public_ip
}

output "security_group_id" {
  description = "ID of the web-portal security group"
  value       = aws_security_group.web_portal_public_sg.id
}

output "ebs_attachment_device" {
  description = "Device name of the attached EBS volume"
  value       = aws_volume_attachment.web_portal_ebs_attachment.device_name
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile attached to the EC2 instance"
  value       = aws_iam_instance_profile.web_portal_instance_profile.name
}
