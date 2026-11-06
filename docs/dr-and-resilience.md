# Disaster recovery and resilience

Strategy: backup-and-restore plus warm data (pilot light for data, not for compute). Targets: **RTO 4 h, RPO 15 min** (all layers). 

| Layer | Mechanism | Notes |
|---|---|---|
| Processed media | S3 CRR to eu-west-1, delete markers replicated | CloudFront origin group fails over on 500/502/503/504 |
| Metadata | DynamoDB global table replica (`enable_dynamodb_replica`) | af-south-1 support unverified |
| Relational | Aurora Global secondary (`enable_aurora`) | Managed switchover/failover |
| Backups | AWS Backup daily, copied to eu-west-1 vault | 35 d dev/stage, 365 d prod |
| Detection | Route 53 health check on `/api/health` -> us-east-1 alarm -> edge topic | Notifies only |

Not covered: Lambda, API Gateway, Step Functions, MediaConvert are not deployed in eu-west-1. In a regional outage they must be re-created there from the same modules (requires a deliberate `primary_region` exception to the approved-region rule, a human decision) or media serving continues read-only from the replica through CloudFront. This is the main gap; see roadmap.

## Failover runbook (summary)
1. Confirm outage (alarm plus AWS Health), declare incident.
2. Viewing continues from the replica bucket automatically for static media.
3. Aurora: `failover-global-cluster` to the eu-west-1 member; update application endpoint.
4. DynamoDB replica is already writable; point re-deployed API at it.
5. Re-create workflow modules in eu-west-1 if uploads must continue.
6. Fail back: reverse replication direction, validate, switch.
