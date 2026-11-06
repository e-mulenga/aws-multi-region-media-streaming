# FinOps and KMS analysis

Development and Test environments use AWS-managed encryption keys to reduce AWS KMS operational costs and management overhead while maintaining encryption at rest. Production environments use Customer Managed Keys (CMKs) to satisfy governance, auditability, compliance, separation-of-duties, and enterprise security requirements.

| Resource | dev | stage/prod |
|---|---|---|
| S3 buckets | SSE-S3 | SSE-KMS, LZ `s3` key, bucket keys on |
| S3 replica | SSE-S3 | SSE-KMS, eu-west-1 key from `dr_kms_key_arns.s3` |
| DynamoDB | AWS-managed key | LZ key (assumption: `analytics`) |
| Aurora, master secret | AWS-managed `aws/rds`, `aws/secretsmanager` | LZ `rds` key |
| Backup vaults | `aws/backup` | LZ `backup` key, eu-west-1 key for DR vault |
| Lambda env, log groups | service default | LZ `s3` key (assumption) |

Cost levers (qualitative; no prices are asserted here because they were not re-checked): CMKs bill per key per month plus requests, so S3 bucket keys are enabled; Aurora global database, Shield Advanced (flat monthly subscription) and CloudFront price class `PriceClass_All` are the largest optional lines. `PriceClass_All` is the default because lower classes exclude African edge locations, which is the audience. MediaConvert is on-demand, Lambda arm64, DynamoDB on-demand, Origin Shield off, MediaPackage off, Aurora off by default. Cross-region replication and Backup copy add inter-region transfer charges.

Key policies are owned by the Landing Zone: they must allow the S3, DynamoDB, Lambda, CloudWatch Logs, Backup and RDS service principals.
