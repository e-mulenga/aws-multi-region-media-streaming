# Threat model (STRIDE, abbreviated)

Scope: ingest, transcode, publish, playback, catalogue and analytics API, DR copies.

| # | Threat | Category | Control | Residual |
|---|---|---|---|---|
| 1 | Anonymous upload of malicious or huge files | Tampering / DoS | Ingestion bucket is private, uploads only via pre-signed URLs issued by an authenticated service; lifecycle expiry; EventBridge suffix filter | Pre-signed URL service is not in this repo |
| 2 | Direct access to media buckets bypassing CloudFront | Info disclosure | Block Public Access, OAC-only bucket policy, TLS-deny | None known |
| 3 | Volumetric / L7 attack on edge | DoS | WAF rate limit + managed rules, optional Shield Advanced | Shield Advanced off by default |
| 4 | Unauthenticated writes to catalogue | Spoofing / Tampering | JWT authorizer on write routes when `jwt_issuer` set | Dev may run without it; analytics POST is deliberately open (rate-limited) |
| 5 | Bypass of WAF by calling the execute-api URL directly | Elevation | API throttling, JWT on writes | Direct URL stays reachable (ADR-005) |
| 6 | Stolen MediaPackage origin access | Info disclosure | CDN authorization secret, rotated via Secrets Manager | Secret also sits in CloudFront origin config and Terraform state |
| 7 | Over-broad IAM | Elevation | Roles scoped to named buckets/tables/queue; PassRole conditioned on service | MediaConvert `CreateJob` scoped to account-level ARN pattern |
| 8 | Data loss or regional outage | Availability | Versioning, CRR, global table, Backup copy, Aurora Global | RPO/RTO below are targets, not measured |
| 9 | Secrets in code or state | Info disclosure | No secrets in repo, gitleaks, Aurora master password managed by RDS | CDN identifier is in state: protect the state bucket |
| 10 | Tampering with state or plan | Tampering | State in Landing Zone bucket, lockfile, CI is validate-only | Apply path is manual |
| 11 | Alarm blind spot at the edge | Repudiation | Dedicated us-east-1 topic (alarms cannot cross regions) | Topic is not CMK-encrypted; add subscriptions |
