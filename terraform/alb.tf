# terraform/alb.tf
# HTTP-only ALB. CloudFront handles HTTPS termination for the user.
# CloudFront → ALB over HTTP on port 80 is the correct setup when you
# don't have an ACM cert yet. Add HTTPS listener here later once you have a domain + cert.

resource "aws_lb" "main" {
  name                   = "securebankapp-alb"
  internal               = false
  load_balancer_type     = "application"
  security_groups        = [aws_security_group.alb.id]
  subnets                = [for s in aws_subnet.public : s.id]

  enable_deletion_protection = false

  tags = {
    Name        = "securebankapp-alb"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "app" {
  name        = "securebankapp-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 5
  }

  tags = {
    Name = "securebankapp-tg"
  }

}

# HTTP Listener (port 80) – FORWARDS to the app.
# CloudFront hits this. CloudFront itself handles HTTPS for the end user.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# HTTPS Listener – add later when you have an ACM cert + domain
# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = 443
#   protocol          = "HTTPS"
#   certificate_arn   = aws_acm_certificate_validation.main.certificate_arn
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app.arn
#   }
# }
