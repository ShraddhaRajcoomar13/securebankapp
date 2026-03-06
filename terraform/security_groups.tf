# terraform/security_groups.tf

# ALB Security Group
# Port 80 open to internet — CloudFront hits port 80 on the ALB.
# Port 443 kept open for when you add the HTTPS listener later.
resource "aws_security_group" "alb" {
  name        = "alb-sg-2"
  description = "ALB - HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from CloudFront / internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS (for when cert is added)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "alb-sg-2"
    Project = "SecureBankApp"
  }
}

# EC2 App Server SG: only traffic from ALB on port 8000
resource "aws_security_group" "app" {
  name        = "app-sg"
  description = "App servers - only from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "App port from ALB only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "app-sg"
    Project = "SecureBankApp"
  }
}

# RDS Security Group: only from EC2 app servers
resource "aws_security_group" "rds" {
  name        = "rds-sg"
  description = "RDS - only from app servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "PostgreSQL from app only"
  }

  tags = {
    Name    = "rds-sg"
    Project = "SecureBankApp"
  }
}

# Lambda SG (for fraud detection inside VPC — Phase 9)
resource "aws_security_group" "lambda" {
  name        = "lambda-sg"
  description = "Lambda fraud detection"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.app.id]
    description     = "From app servers"
  }

  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
    description     = "To RDS"
  }

  tags = {
    Name    = "lambda-sg"
    Project = "SecureBankApp"
  }
}
