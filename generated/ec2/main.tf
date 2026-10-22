# ./generated/ec2/main.tf
# Managed by Terraform – EC2 / ALB stack for web-portal

###############################################################################
# Data sources
###############################################################################

data "aws_vpc" "main" {
  tags = {
    Name = "main-vpc"
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

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

###############################################################################
# Local values
###############################################################################

locals {
  common_tags = {
    Environment        = "production"
    Application        = "web-portal"
    Owner              = "it-operations-team"
    CostCenter         = "IT-OPS-003"
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

###############################################################################
# Security Groups
###############################################################################

resource "aws_security_group" "alb" {
  name        = "web-portal-alb-sg"
  description = "Security group for web-portal ALB – DMZ web tier"
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
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-alb-sg"
  })
}

resource "aws_security_group" "ec2_web" {
  name        = "web-portal-ec2-sg"
  description = "Security group for web-portal EC2 instances"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-ec2-sg"
  })
}

###############################################################################
# IAM Role & Instance Profile
###############################################################################

resource "aws_iam_role" "ec2_web_portal" {
  name = "ec2-web-portal-role"

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
    Name = "ec2-web-portal-role"
  })
}

resource "aws_iam_role_policy_attachment" "ec2_web_portal_ssm" {
  role       = aws_iam_role.ec2_web_portal.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_web_portal_cw" {
  role       = aws_iam_role.ec2_web_portal.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_web_portal" {
  name = "ec2-web-portal-instance-profile"
  role = aws_iam_role.ec2_web_portal.name

  tags = merge(local.common_tags, {
    Name = "ec2-web-portal-instance-profile"
  })
}

###############################################################################
# Launch Template
###############################################################################

resource "aws_launch_template" "web_portal" {
  name_prefix   = "web-portal-lt-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.medium"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_web_portal.name
  }

  vpc_security_group_ids = [aws_security_group.ec2_web.id]

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.common_tags, {
      Name = "web-portal-instance"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(local.common_tags, {
      Name = "web-portal-volume"
    })
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-launch-template"
  })

  lifecycle {
    create_before_destroy = true
  }
}
