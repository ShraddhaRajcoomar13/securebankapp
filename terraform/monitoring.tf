# terraform/monitoring.tf
# =============================
# S3 Bucket for Logs (ALB, Redshift, CloudTrail)
# =============================

# Generate random suffix for globally unique bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "logs" {
  bucket = "securebankapp-logs-${random_id.bucket_suffix.hex}"
  
  force_destroy = true  # Convenient for portfolio/testing - allows destroy even with objects

  tags = {
    Name        = "securebankapp-logs"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

# Block all public access to logs bucket
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for safety (can recover deleted/overwritten logs)
resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # Use AES256, NOT KMS (simpler for logs)
    }
  }
}

# Lifecycle policy to manage costs - FIXED: added required filter
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"
    
    # REQUIRED: filter must be specified
    filter {}  # Empty filter applies to all objects

    # Move to cheaper storage after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete after 365 days (adjust for compliance requirements)
    expiration {
      days = 365
    }
  }
}

# Bucket policy to allow Redshift logging
resource "aws_s3_bucket_policy" "logs_redshift" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RedshiftAuditLogging"
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
        Action = [
          "s3:PutObject",
          "s3:GetBucketAcl"
        ]
        Resource = [
          aws_s3_bucket.logs.arn,
          "${aws_s3_bucket.logs.arn}/*"
        ]
      },
      # ALB logging permissions
      {
        Sid    = "ALBAccessLogging"
        Effect = "Allow"
        Principal = {
          Service = "elasticloadbalancing.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/*"
      }
    ]
  })
}

# =============================
# CloudWatch Log Groups - NO KMS (causes permission issues)
# =============================

resource "aws_cloudwatch_log_group" "app" {
  name              = "/securebankapp/app"
  retention_in_days = 90
  # REMOVED kms_key_id - CloudWatch Logs KMS requires complex IAM permissions

  tags = {
    Name        = "securebankapp-app-logs"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "rds" {
  name              = "/aws/rds/cluster/securebankapp/postgresql"
  retention_in_days = 365  # 1 year for compliance
  # REMOVED kms_key_id

  tags = {
    Name        = "securebankapp-rds-logs"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

# =============================
# SNS Topics for Alerts
# =============================

resource "aws_sns_topic" "alerts" {
  name = "securebankapp-alerts"

  tags = {
    Name        = "securebankapp-alerts"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

resource "aws_sns_topic" "fraud_alerts" {
  name = "securebankapp-fraud-alerts"

  tags = {
    Name        = "securebankapp-fraud-alerts"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

# =============================
# CloudWatch Alarms
# =============================

# Alarm 1: High CPU on EC2 instances
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "securebankapp-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "EC2 CPU above 85% for 4 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}

# Alarm 2: ALB 5XX Error Rate
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "securebankapp-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "More than 10 5XX errors in 1 minute"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

# Alarm 3: RDS Free Storage Space
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "securebankapp-rds-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5000000000  # 5GB in bytes
  alarm_description   = "RDS free storage below 5GB"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
}

# Alarm 4: Unhealthy Target Count
resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name          = "securebankapp-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "One or more targets are unhealthy"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
}
