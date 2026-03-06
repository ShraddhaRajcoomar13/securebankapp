# terraform/github_actions.tf

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions" {
  name = "securebankapp-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:ShraddhaRajcoomar13/securebankapp:*"
        }
      }
    }]
  })

  tags = {
    Name        = "securebankapp-github-actions"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name = "securebankapp-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR - push images
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = aws_ecr_repository.app.arn
      },
      # ECS - force new deployment (replaces ASG refresh for ECS-based deploys)
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = "arn:aws:ecs:us-east-1:${data.aws_caller_identity.current.account_id}:service/securebankapp-cluster/securebankapp-service"
      },
      # ECS cluster describe (required by update-service)
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeClusters"]
        Resource = "arn:aws:ecs:us-east-1:${data.aws_caller_identity.current.account_id}:cluster/securebankapp-cluster"
      }
    ]
  })
}
