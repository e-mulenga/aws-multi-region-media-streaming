# Module: media-package - live channel + HLS origin endpoint, deployed from eu-west-1
# (service not available in af-south-1).
#
# The AWS provider has no origin-endpoint resource for MediaPackage v1, so the endpoint is created
# through a CloudFormation stack (AWS::MediaPackage::OriginEndpoint). The original repository used
# resource types that do not exist; that is fixed here.
# MediaPackage v2 (channel groups) is a roadmap item.

resource "aws_media_package_channel" "live" {
  channel_id  = "${var.name_prefix}-live"
  description = "Live ingest channel"
}

# Shared secret between CloudFront and MediaPackage (CDN authorization).
resource "random_password" "cdn_identifier" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "cdn" {
  name                    = "${var.name_prefix}/mediapackage-cdn-identifier"
  description             = "CloudFront to MediaPackage CDN authorization"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "cdn" {
  secret_id = aws_secretsmanager_secret.cdn.id

  secret_string = jsonencode({
    MediaPackageCDNIdentifier = random_password.cdn_identifier.result
  })
}

resource "aws_iam_role" "secrets_access" {
  name = "${var.name_prefix}-mediapackage-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "mediapackage.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "secrets_access" {
  name = "read-cdn-secret"
  role = aws_iam_role.secrets_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret", "secretsmanager:ListSecretVersionIds"]
        Resource = [aws_secretsmanager_secret.cdn.arn]
      }],
      var.kms_key_arn == null ? [] : [{
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [var.kms_key_arn]
      }]
    )
  })
}

resource "aws_cloudformation_stack" "endpoint" {
  name = "${var.name_prefix}-mediapackage-endpoint"

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Resources = {
      HlsEndpoint = {
        Type = "AWS::MediaPackage::OriginEndpoint"
        Properties = {
          Id                     = "${var.name_prefix}-hls"
          ChannelId              = aws_media_package_channel.live.id
          ManifestName           = "index"
          StartoverWindowSeconds = 86400
          TimeDelaySeconds       = 0
          HlsPackage = {
            SegmentDurationSeconds = var.hls_segment_duration
            PlaylistType           = "EVENT"
            PlaylistWindowSeconds  = 60
          }
          Authorization = {
            CdnIdentifierSecret = aws_secretsmanager_secret.cdn.arn
            SecretsRoleArn      = aws_iam_role.secrets_access.arn
          }
        }
      }
    }
    Outputs = {
      EndpointUrl = {
        Value = { "Fn::GetAtt" = ["HlsEndpoint", "Url"] }
      }
    }
  })

  depends_on = [aws_secretsmanager_secret_version.cdn, aws_iam_role_policy.secrets_access]
}
