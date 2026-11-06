# Regional availability (af-south-1) and the Ireland rule

A service that is not available or not GA in af-south-1 is deployed from eu-west-1 (Ireland, the DR region) with the `ireland` provider alias, labelled "deployed from eu-west-1 (service not available in af-south-1)". No other region is approved.

Checked 2026-11-05 against AWS documentation.

| Service | af-south-1 | Source | Deployed from |
|---|---|---|---|
| Elemental MediaConvert | Yes, since 2022-12-19 | [What's New](https://aws.amazon.com/about-aws/whats-new/2022/12/aws-elemental-mediaconvert-available-africa-cape-town-region) | af-south-1 |
| Elemental MediaPackage (v1 live/VOD and v2) | **No**: not in any endpoint table; eu-west-1 is | [MediaPackage endpoints](https://docs.aws.amazon.com/general/latest/gr/mediapackage.html) | **eu-west-1** |
| Aurora PostgreSQL Global Database | Yes (Cape Town and Ireland both listed; Cape Town needs 16.1+ for PG 16) | [Aurora Global regions](https://docs.amazonaws.cn/en_us/AmazonRDS/latest/AuroraUserGuide/Concepts.Aurora_Fea_Regions_DB-eng.Feature.GlobalDatabase.html) | af-south-1 primary, eu-west-1 secondary |
| Step Functions | Yes (`states.af-south-1`) | [Endpoints and quotas](https://docs.aws.amazon.com/general/latest/gr/step-functions.html) | af-south-1 |
| AWS WAF, Shield Advanced | Yes, since 2020-09-01 | [What's New](https://aws.amazon.com/about-aws/whats-new/2020/09/aws-waf-aws-shield-advanced-available-cape-town-milano/) | see below (CloudFront scope is global) |
| Lambda, API Gateway HTTP API, EventBridge, X-Ray, Secrets Manager, CloudWatch, S3, SNS | Core services, assumed available | **not individually re-verified today** | af-south-1 |
| DynamoDB global tables (af-south-1 <-> eu-west-1) | **Not verified** | search returned no authoritative page | af-south-1 table, replica behind `enable_dynamodb_replica` |
| AWS Backup, incl. cross-region copy to eu-west-1 | **Not verified** | search only | af-south-1 vault, copy to eu-west-1 |
| Origin Shield region | **Not verified** for af-south-1; default `eu-west-1`, feature off by default | - | n/a |

## Global-service control plane (not a deployment region)

CloudFront, WAFv2 with `CLOUDFRONT` scope, CloudFront CloudWatch metrics and Route 53 health-check metrics are only addressable through us-east-1. The `global_edge` provider alias is used for exactly these. Nothing else is placed there: no compute, no data. This is a control-plane exception, not approval of us-east-1 as a workload region. The Landing Zone's CloudFront certificate is already in us-east-1.

## Things to verify before first apply

1. DynamoDB global tables between af-south-1 and eu-west-1. If unsupported, set `enable_dynamodb_replica = false`; AWS Backup copy remains the DR path for metadata.
2. AWS Backup cross-region copy af-south-1 -> eu-west-1.
3. Aurora engine minor version (`aurora_engine_version`) and instance class availability in both regions.
4. MediaPackage v1 availability for new accounts (v2 migration is on the roadmap).
