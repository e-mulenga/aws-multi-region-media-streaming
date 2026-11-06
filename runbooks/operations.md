# Operations runbook

**Stuck or failed transcode:** check the Step Functions execution (`<prefix>-media-processing`), then the MediaConvert job; the notification Lambda marks the item `FAILED`. Re-upload to retry.

**CDN 5xx alarm (us-east-1 topic):** check origin health (S3, API), WAF blocked requests, and whether CloudFront is already failing over to the eu-west-1 replica.

**Primary unhealthy alarm:** follow `docs/dr-and-resilience.md`; failover is a human decision.

**Rotate MediaPackage CDN secret:** `tofu apply -replace=module.media_package[0].random_password.cdn_identifier`; CloudFront and the secret update together.
