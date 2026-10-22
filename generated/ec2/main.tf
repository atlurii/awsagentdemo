# ./generated/ec2/main.tf
# Generated Terraform configuration for EC2 web-portal infrastructure

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
    Environment         = "production"
    Application         = "web-portal"
    Owner               = "it-operations-team"
    CostCenter          = "IT-OPS-003"
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

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["main-vpc"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Tier"
    values = ["private"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Tier"
    values = ["public"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

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
    description = "HTTP from internet"
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
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "web-portal-ec2-sg"
  })
}

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

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_web_portal.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
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

resource "aws_launch_template" "web_portal" {
  name_prefix   = "web-portal-lt-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.medium"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_web_portal.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2_web.id]
  }

  monitoring {
    enabled = true
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
}

resource "aws_autoscaling_group" "web_portal" {
  name                = "web-portal-asg"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 1
  vpc_zone_identifier = data.aws_subnets.private.ids

  launch_template {
    id      = aws_launch_template.web_portal.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  dynamic "tag" {
    for_each = merge(local.common_tags, {
      Name = "web-portal-asg"
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
