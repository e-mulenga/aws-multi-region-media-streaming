# Roadmap

1. Run `terraform validate` and a dev plan; fix whatever the real providers report (highest priority).
2. Verify DynamoDB global tables and AWS Backup copy for af-south-1 <-> eu-west-1; adjust flags.
3. Landing Zone: export CMKs (and eu-west-1 keys), eu-west-1 certificate, a us-east-1 topic, endpoints.
4. Origin-verify header between CloudFront and the API; JWT mandatory outside dev.
5. Move to MediaPackage v2 (channel groups) and add a DR-region compute stack for uploads.
6. Pre-signed upload service and per-title DRM (the original had a DRM flag with no implementation; removed).
7. Replace the content `Scan` search with an index (OpenSearch or GSI design).
8. Automated DR drill and measured RTO/RPO.
