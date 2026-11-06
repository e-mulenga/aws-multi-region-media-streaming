# Landing Zone integration

Everything shared is read from the Landing Zone Terraform state through `terraform_remote_state` (`landing_zone.tf`). Nothing in this table is created here.

| Landing Zone output | Used for |
|---|---|
| `contract_schema_version` | Guard: plan fails if it is not the expected version (`2`) |
| `af_south_1.{vpc_id,vpc_cidr_block,db_subnet_group}` | Aurora primary placement and security group |
| `eu_west_1.{vpc_id,vpc_cidr_block,db_subnet_group}` | Aurora secondary placement and security group |
| `route53_zone_id` | CloudFront alias records |
| `acm_cloudfront_certificate_arn` (us-east-1) | CloudFront viewer certificate when aliases are set |
| `monitoring_topic_arn` (af-south-1) | Alarm actions for MediaConvert, workflow and API alarms; Lambda notifications |
| `key_strategy`, `shared_kms_keys` | dev: AWS-managed keys; stage/prod: CMKs, mapped via `kms_key_domains` |
| `access_logs_bucket_name` | Optional CloudFront standard logging |

Not consumed, and why: `private_subnet_ids`/`public_subnet_ids` (Lambda is not VPC-attached, ADR-004), `ecr_repository_urls` (no containers), `github_oidc_provider_arn` (CI is validate-only; no deploy role exists in the Landing Zone export, `github_oidc_role_arns` is empty), `log_buckets` (all in us-east-1).