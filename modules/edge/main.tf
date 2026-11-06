# Module: edge - CloudFront + WAF (global control plane in us-east-1).
# Origins: S3 processed (OAC, with eu-west-1 replica failover), HTTP API (/api/*), optional MediaPackage (/out/*).
# AWS WAF cannot be associated with API Gateway HTTP APIs, so the API is protected by fronting it with CloudFront.

locals {
  has_aliases  = length(var.aliases) > 0
  has_failover = var.processed_dr_bucket_domain != null
  has_live     = var.media_package_domain != null
  s3_target    = local.has_failover ? "s3-group" : "s3-primary"

  # AWS managed policy IDs
  cache_optimized        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cache_disabled         = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  origin_all_but_host    = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  response_security_hdrs = "67f7725c-6f97-4210-82d7-5512b31e9d03"
}

# ---- WAF (CLOUDFRONT scope) ----
resource "aws_wafv2_web_acl" "cdn" {
  name  = "${var.name_prefix}-cdn"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = {
      common        = { priority = 10, name = "AWSManagedRulesCommonRuleSet" }
      bad-inputs    = { priority = 20, name = "AWSManagedRulesKnownBadInputsRuleSet" }
      ip-reputation = { priority = 30, name = "AWSManagedRulesAmazonIpReputationList" }
    }

    content {
      name     = rule.key
      priority = rule.value.priority

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-cdn"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudwatch_log_group" "waf" {
  # Name must start with aws-waf-logs-. No CMK exists in us-east-1 in the Landing Zone export.
  name              = "aws-waf-logs-${var.name_prefix}"
  retention_in_days = var.log_retention_days
}

resource "aws_wafv2_web_acl_logging_configuration" "cdn" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.cdn.arn

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
}

# ---- CloudFront ----
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.name_prefix}-s3"
  description                       = "OAC for the processed media buckets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_cache_policy" "live" {
  count = local.has_live ? 1 : 0

  name        = "${var.name_prefix}-live"
  comment     = "Short default TTL for live manifests; honours origin Cache-Control"
  default_ttl = 5
  min_ttl     = 0
  max_ttl     = 86400

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.name_prefix} media platform"
  price_class     = var.price_class
  aliases         = var.aliases
  web_acl_id      = aws_wafv2_web_acl.cdn.arn
  http_version    = "http2and3"

  origin {
    origin_id                = "s3-primary"
    domain_name              = var.processed_bucket_domain
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id

    dynamic "origin_shield" {
      for_each = var.enable_origin_shield ? [1] : []

      content {
        enabled              = true
        origin_shield_region = var.origin_shield_region
      }
    }
  }

  dynamic "origin" {
    for_each = local.has_failover ? [1] : []

    content {
      origin_id                = "s3-dr"
      domain_name              = var.processed_dr_bucket_domain
      origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
    }
  }

  dynamic "origin_group" {
    for_each = local.has_failover ? [1] : []

    content {
      origin_id = "s3-group"

      failover_criteria {
        status_codes = [500, 502, 503, 504]
      }

      member {
        origin_id = "s3-primary"
      }

      member {
        origin_id = "s3-dr"
      }
    }
  }

  origin {
    origin_id   = "api"
    domain_name = var.api_domain

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  dynamic "origin" {
    for_each = local.has_live ? [1] : []

    content {
      origin_id   = "media-package"
      domain_name = var.media_package_domain

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }

      custom_header {
        name  = "X-MediaPackage-CDNIdentifier"
        value = var.media_package_cdn_identifier
      }
    }
  }

  default_cache_behavior {
    target_origin_id           = local.s3_target
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.cache_optimized
    response_headers_policy_id = local.response_security_hdrs
  }

  ordered_cache_behavior {
    path_pattern               = "/api/*"
    target_origin_id           = "api"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.cache_disabled
    origin_request_policy_id   = local.origin_all_but_host
    response_headers_policy_id = local.response_security_hdrs
  }

  dynamic "ordered_cache_behavior" {
    for_each = local.has_live ? [1] : []

    content {
      path_pattern               = "/out/*"
      target_origin_id           = "media-package"
      viewer_protocol_policy     = "redirect-to-https"
      allowed_methods            = ["GET", "HEAD", "OPTIONS"]
      cached_methods             = ["GET", "HEAD"]
      compress                   = true
      cache_policy_id            = aws_cloudfront_cache_policy.live[0].id
      response_headers_policy_id = local.response_security_hdrs
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = length(var.allowed_countries) > 0 ? "whitelist" : "none"
      locations        = var.allowed_countries
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = local.has_aliases ? null : true
    acm_certificate_arn            = local.has_aliases ? var.certificate_arn : null
    ssl_support_method             = local.has_aliases ? "sni-only" : null
    minimum_protocol_version       = local.has_aliases ? "TLSv1.2_2021" : null
  }

  dynamic "logging_config" {
    for_each = var.logging_bucket_domain == null ? [] : [1]

    content {
      bucket          = var.logging_bucket_domain
      prefix          = "cloudfront/${var.name_prefix}/"
      include_cookies = false
    }
  }
}

resource "aws_shield_protection" "cdn" {
  count = var.enable_shield_advanced ? 1 : 0

  name         = "${var.name_prefix}-cdn"
  resource_arn = aws_cloudfront_distribution.main.arn
}

# ---- DNS (Landing Zone zone, aliases must be inside it) ----
resource "aws_route53_record" "alias_a" {
  for_each = toset(var.aliases)

  zone_id = var.route53_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alias_aaaa" {
  for_each = toset(var.aliases)

  zone_id = var.route53_zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# ---- Alerting (us-east-1: CloudFront metrics and Route 53 health-check metrics only exist here) ----
# The Landing Zone topic is in af-south-1 and CloudWatch alarms cannot notify cross-region topics.
# #tfsec:ignore:aws-sns-enable-topic-encryption
# checkov:skip=CKV_AWS_26: CloudWatch alarms cannot publish to topics encrypted with an AWS-managed key and the Landing Zone exports no us-east-1 CMK. Topic carries alarm metadata only.
resource "aws_sns_topic" "edge_alerts" {
  name = "${var.name_prefix}-edge-alerts"
}

resource "aws_sns_topic_subscription" "edge_email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.edge_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "cdn_5xx" {
  alarm_name          = "${var.name_prefix}-cdn-5xx-rate"
  alarm_description   = "CloudFront 5xx error rate above 1%."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.edge_alerts.arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
    Region         = "Global"
  }
}

resource "aws_cloudwatch_metric_alarm" "cdn_origin_latency" {
  alarm_name          = "${var.name_prefix}-cdn-origin-latency"
  alarm_description   = "CloudFront p99 origin latency above 3 s. Origin latency metrics require the additional-metrics option on the distribution."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "OriginLatency"
  namespace           = "AWS/CloudFront"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 3000
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.edge_alerts.arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
    Region         = "Global"
  }
}
