# terraform/cloudfront.tf
# CloudFront handles HTTPS from the user (free *.cloudfront.net cert).
# CloudFront → ALB uses HTTP on port 80 — ALB has no HTTPS listener yet.
# This is safe: the public-internet leg is encrypted by CloudFront.

resource "aws_cloudfront_distribution" "app" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "SecureBankApp via ALB"
  default_root_object = ""

  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"   # ALB only has port 80 right now
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"  # Users always get HTTPS

    forwarded_values {
      query_string = true
      cookies { forward = "all" }
      headers      = ["Host", "Authorization", "Origin", "Referer"]
    }

    min_ttl     = 0
    default_ttl = 0   # No caching for a dynamic API
    max_ttl     = 0
    compress    = true
  }

  viewer_certificate {
    cloudfront_default_certificate = true   # Free *.cloudfront.net SSL
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  tags = {
    Name        = "securebankapp-cf"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}
