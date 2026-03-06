
variable "aws_region" {
  default = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "domain_name" {
  description = "Your domain (must be managed in Route 53)"
  type        = string
  default = "https://d1a2b3c4d5e6f.cloudfront.net"
  # example: "securebankapp.com"
}