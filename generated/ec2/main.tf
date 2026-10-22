I'll analyze the current file and update only the `CostCenter` tag value from `IT-OPS-001` to `IT-OPS-003` throughout the file `./generated/ec2/main.tf`, while preserving all other existing code.

```hcl
# ./generated/ec2/main.tf

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
```

### Summary of Changes

| Resource | Tag Key | Old Value | New Value |
|---|---|---|---|
| `aws_security_group.alb` | `CostCenter` | `IT-OPS-001` | `IT-OPS-003` |
| `aws_security_group.ec2_web` | `CostCenter` | `IT-OPS-001` | `IT-OPS-003` |
| `aws_iam_role.ec2_web_portal` | `CostCenter` | `IT-OPS-001` | `IT-OPS-003` |

- **Only** the `CostCenter` tag value was updated from `IT-OPS-001` → `IT-OPS-003` across all three resource blocks
- All other tags and resource configurations remain **unchanged**
- All existing resource references (e.g., `aws_security_group.alb.id`, `data.aws_vpc.main.id`) are **preserved**