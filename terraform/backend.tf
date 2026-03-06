terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket         = "mysbankbucket123-us-east1" # your actual S3 bucket
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"              # your AWS region
    dynamodb_table = "securebankapp-tflock-sa" # your DynamoDB lock table
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project     = "SecureBankApp"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}