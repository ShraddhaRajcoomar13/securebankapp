# terraform/kms.tf

resource "aws_kms_key" "main" {
  description             = "SecureBankApp main encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  is_enabled              = true

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "securebankapp-kms-key-policy"
    Statement = [
      {
        Sid       = "Enable IAM User Permissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "Allow EC2 service for EBS encryption"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey","kms:CreateGrant"]
        Resource  = "*"
      },
      {
        Sid       = "Allow EC2 role"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.ec2_role.arn }
        Action    = ["kms:Decrypt","kms:Encrypt","kms:GenerateDataKey","kms:DescribeKey","kms:CreateGrant"]
        Resource  = "*"
      },
      {
        Sid       = "Allow RDS and Redshift"
        Effect    = "Allow"
        Principal = { Service = ["rds.amazonaws.com", "redshift.amazonaws.com"] }
        Action    = ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey","kms:CreateGrant"]
        Resource  = "*"
      },
      {
        Sid       = "Allow Secrets Manager"
        Effect    = "Allow"
        Principal = { Service = "secretsmanager.amazonaws.com" }
        Action    = ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey","kms:CreateGrant"]
        Resource  = "*"
      },
      {
        Sid       = "Allow CloudWatch Logs"
        Effect    = "Allow"
        Principal = { Service = "logs.us-east-1.amazonaws.com" }
        Action    = ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey"]
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"
          }
        }
        Resource  = "*"
      },
      {
        Sid       = "Allow CloudTrail"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey"]
        Resource  = "*"
      },
      {
        Sid       = "Allow Lambda"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = ["kms:Decrypt","kms:GenerateDataKey","kms:DescribeKey"]
        Resource  = "*"
      }
    ]
  })

  tags = {
    Name        = "securebankapp-main-key"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/securebankapp"
  target_key_id = aws_kms_key.main.key_id
}
