# Architecture decision records

## ADR-001 Consume the Landing Zone, never recreate
Status: accepted. Network, DNS, certificate, alert topic and key strategy are read from remote state. A `terraform_data` guard fails the plan on contract-version, region or key-strategy mismatch. Consequence: stage/prod cannot plan until the Landing Zone exports CMKs.

## ADR-002 af-south-1 primary, Ireland for DR and for unavailable services
Status: accepted. MediaPackage is not offered in af-south-1, so it is deployed from eu-west-1 through the `ireland` alias. Same alias holds the S3 replica, DynamoDB replica, Aurora secondary and DR backup vault. Evidence and date: `regional-availability.md`.

## ADR-003 CloudFront, WAF and edge alarms through a us-east-1 control-plane alias
Status: accepted as a narrow exception. These services are global but addressable only via us-east-1. No workload is placed there.

## ADR-004 Lambda is not attached to the VPC
Status: accepted. The Landing Zone has no NAT and no interface endpoints; the functions only call DynamoDB, S3, MediaConvert, SNS, which are reachable through service endpoints without a VPC. 

## ADR-005 API protected by fronting it with CloudFront
Status: accepted. AWS WAF cannot be associated with API Gateway HTTP APIs (the original repository attempted it with an invalid ARN). The API is exposed under `/api/*` on the distribution, covered by the CloudFront web ACL. The `execute-api` URL stays reachable directly; throttling and the JWT authorizer apply either way. Open improvement: origin-verify header (roadmap).

## ADR-006 MediaPackage endpoint via CloudFormation
Status: accepted. The AWS provider has the v1 channel but no origin-endpoint resource, and the original used resource types that do not exist. The endpoint is a CloudFormation stack in eu-west-1. MediaPackage v2 is a roadmap item.

## ADR-007 Dev/Test AWS-managed keys, prod CMKs
Status: accepted (organisation rule). S3 in dev uses SSE-S3, DynamoDB/Aurora/Secrets Manager use their AWS-managed keys. Detail: `finops-and-kms.md`.

## ADR-008 Aurora optional and off by default
Status: accepted. No code path reads Aurora yet and a global cluster is the largest cost line; the original wired a secret into Lambda that could not reach a VPC database. Enable it when a relational catalogue is built.

## ADR-009 Failover is a human decision
Status: accepted. The Route 53 alarm notifies; promotion of Aurora, DNS or application re-deploy follows the runbook. Automatic regional failover is not implemented.
