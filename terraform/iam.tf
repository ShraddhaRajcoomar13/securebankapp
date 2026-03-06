# terraform/iam.tf

# =============================
# EC2 Instance Role & Profile (for EC2 instances in ASG)
# =============================
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "ec2_role" {
  name = "securebankapp-ec2-role"

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

  tags = {
    Name        = "securebankapp-ec2-role"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

resource "aws_iam_instance_profile" "ec2" {
  name = "securebankapp-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Inline policy for EC2 instances: ECR pull, Secrets Manager, Logs, KMS
resource "aws_iam_role_policy" "ec2_main_policy" {
  name = "securebankapp-ec2-main-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR pull permissions (for ECS agent and manual pulls if needed)
      {
        Effect   = "Allow"
        Action   = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },

      # Secrets Manager – read DB & JWT secrets
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = [
          "arn:aws:secretsmanager:*:*:secret:securebankapp/db-password-*",
          "arn:aws:secretsmanager:*:*:secret:securebankapp/jwt-secret-*"
          # Best practice: use exact ARNs once defined in Terraform
          # aws_secretsmanager_secret.db_password.arn,
          # aws_secretsmanager_secret.jwt_secret.arn
        ]
      },

      # CloudWatch Logs – for app and ECS agent logs
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/securebankapp/*:*"
      },

      # KMS – for decrypting secrets, EBS encryption, etc.
      {
        Effect   = "Allow"
        Action   = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}

# Attach managed policy for Session Manager (required for Session Manager access)
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach managed policy for ECS agent on EC2 instances
resource "aws_iam_role_policy_attachment" "ec2_ecs_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# =============================
# ECS Task Execution Role (required for ECS to pull images & write logs)
# =============================
resource "aws_iam_role" "ecs_task_execution" {
  name = "securebankapp-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "securebankapp-ecs-task-execution-role"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

# Attach managed policy for ECS task execution (ECR pull + CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================
# ECS Task Role (optional – for app-level permissions like S3, DB access)
# =============================
resource "aws_iam_role" "ecs_task_role" {
  name = "securebankapp-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "securebankapp-ecs-task-role"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

# Example policy for task role – add permissions your app needs (e.g. S3, RDS)
resource "aws_iam_role_policy" "ecs_task_app_policy" {
  name = "securebankapp-ecs-task-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = [
          "arn:aws:secretsmanager:*:*:secret:securebankapp/db-password-*",
          "arn:aws:secretsmanager:*:*:secret:securebankapp/jwt-secret-*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}
# =============================
# RDS Enhanced Monitoring Role
# =============================
resource "aws_iam_role" "rds_monitoring" {
  name = "securebankapp-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "monitoring.rds.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "securebankapp-rds-monitoring-role"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_policy" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}


# =============================
# Lambda Execution Role (for fraud detection)
# =============================
resource "aws_iam_role" "lambda_role" {
  name = "securebankapp-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "securebankapp-lambda-role"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "securebankapp-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/securebankapp-*:*"
      },
      # Secrets Manager
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = [
          "arn:aws:secretsmanager:*:*:secret:securebankapp/db-password-*"
        ]
      },
      # KMS - decrypt secrets
      {
        Effect   = "Allow"
        Action   = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.main.arn
      },
      # SNS - publish fraud alerts
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.fraud_alerts.arn
      },
      # VPC - required for Lambda inside VPC
      {
        Effect   = "Allow"
        Action   = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      },
      # X-Ray tracing
      {
        Effect   = "Allow"
        Action   = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      },
      # Lambda invoke permission (for the ECS app to invoke this Lambda)
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = "arn:aws:lambda:us-east-1:${data.aws_caller_identity.current.account_id}:function:securebankapp-fraud-detection"
      }
    ]
  })
}
