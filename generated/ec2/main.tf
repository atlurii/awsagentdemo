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

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["public"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["private"]
  }
}

data "aws_ami" "web_portal" {
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

  tags = {
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

  tags = {
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

  tags = {
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

resource "aws_iam_role_policy_attachment" "ec2_web_portal_ssm" {
  role       = aws_iam_role.ec2_web_portal.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_web_portal_cloudwatch" {
  role       = aws_iam_role.ec2_web_portal.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_web_portal" {
  name = "ec2-web-portal-instance-profile"
  role = aws_iam_role.ec2_web_portal.name

  tags = {
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

resource "aws_launch_template" "web_portal" {
  name_prefix   = "web-portal-lt-"
  image_id      = data.aws_ami.web_portal.id
  instance_type = var.instance_type

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

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y amazon-cloudwatch-agent
    systemctl enable amazon-cloudwatch-agent
    systemctl start amazon-cloudwatch-agent
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
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

  tag_specifications {
    resource_type = "volume"
    tags = {
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

  tags = {
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

resource "aws_lb" "web_portal" {
  name               = "web-portal-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids

  enable_deletion_protection = true

  tags = {
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

resource "aws_lb_target_group" "web_portal" {
  name     = "web-portal-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
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

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.web_portal.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_portal.arn
  }

  tags = {
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

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.web_portal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
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

resource "aws_autoscaling_group" "web_portal" {
  name                = "web-portal-asg"
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  vpc_zone_identifier = data.aws_subnets.private.ids
  target_group_arns   = [aws_lb_target_group.web_portal.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.web_portal.id
    version = "$Latest"
  }

  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }

  tag {
    key                 = "Application"
    value               = "web-portal"
    propagate_at_launch = true
  }

  tag {
    key                 = "Owner"
    value               = "it-operations-team"
    propagate_at_launch = true
  }

  tag {
    key                 = "CostCenter"
    value               = "IT-OPS-003"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "digital-transformation"
    propagate_at_launch = true
  }

  tag {
    key                 = "ServiceLevel"
    value               = "critical"
    propagate_at_launch = true
  }

  tag {
    key                 = "BackupRequired"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "MonitoringEnabled"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "PatchGroup"
    value               = "monthly"
    propagate_at_launch = true
  }

  tag {
    key                 = "ComplianceRequired"
    value               = "sox-gdpr"
    propagate_at_launch = true
  }

  tag {
    key                 = "DataClassification"
    value               = "confidential"
    propagate_at_launch = true
  }

  tag {
    key                 = "BusinessUnit"
    value               = "healthcare-technology"
    propagate_at_launch = true
  }

  tag {
    key                 = "MaintenanceWindow"
    value               = "sunday-02:00-06:00"
    propagate_at_launch = true
  }

  tag {
    key                 = "DisasterRecovery"
    value               = "enabled"
    propagate_at_launch = true
  }

  tag {
    key                 = "SecurityGroup"
    value               = "dmz-web-tier"
    propagate_at_launch = true
  }

  tag {
    key                 = "AutoScaling"
    value               = "enabled"
    propagate_at_launch = true
  }

  tag {
    key                 = "LogRetention"
    value               = "90-days"
    propagate_at_launch = true
  }

  tag {
    key                 = "IncidentPriority"
    value               = "high"
    propagate_at_launch = true
  }

  tag {
    key                 = "ServiceDesk"
    value               = "servicenow-integration"
    propagate_at_launch = true
  }

  tag {
    key                 = "ChangeManagement"
    value               = "required"
    propagate_at_launch = true
  }
}
