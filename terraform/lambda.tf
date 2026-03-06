# terraform/lambda.tf

data "archive_file" "fraud_detection" {
  type        = "zip"
  source_file = "${path.module}/../lambda/fraud_detection.py"
  output_path = "${path.module}/../lambda/fraud_detection.zip"
}

resource "aws_lambda_function" "fraud_detection" {
  filename         = data.archive_file.fraud_detection.output_path
  source_code_hash = data.archive_file.fraud_detection.output_base64sha256
  function_name    = "securebankapp-fraud-detection"
  role             = aws_iam_role.lambda_role.arn
  handler          = "fraud_detection.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 256

  vpc_config {
    subnet_ids         = [for s in aws_subnet.private : s.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST               = aws_db_instance.main.address
      FRAUD_ALERT_TOPIC_ARN = aws_sns_topic.fraud_alerts.arn
      DB_SECRET_ID          = aws_secretsmanager_secret.db_password.id
    }
  }

  kms_key_arn = aws_kms_key.main.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "securebankapp-fraud-detection"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}
