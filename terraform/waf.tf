# terraform/waf.tf

resource "aws_wafv2_web_acl" "main" {
  name        = "securebankapp-waf"
  description = "WAF for SecureBankApp"
  scope       = "REGIONAL" # Use "CLOUDFRONT" if for global CF distribution

  # Default action if no rules match
  default_action {
    allow {}
  }

  # Visibility configuration for metrics/logging
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "securebankapp-waf"
    sampled_requests_enabled   = true
  }

  # --- Example Managed Rule: AWS Managed Common Rule Set (OWASP Top 10) ---
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-managed-common"
      sampled_requests_enabled   = true
    }
  }

  # --- Optional: add more rules here, e.g., RateBasedRule ---
  # rule {
  #   name     = "RateLimitRule"
  #   priority = 2
  #   statement {
  #     rate_based_statement {
  #       limit              = 2000
  #       aggregate_key_type = "IP"
  #     }
  #   }
  #   action {
  #     block {}
  #   }
  #   visibility_config {
  #     cloudwatch_metrics_enabled = true
  #     metric_name                = "rate-limit-rule"
  #     sampled_requests_enabled   = true
  #   }
  # }
}