# Testing strategy

| Level | What | Where | Status |
|---|---|---|---|
| Static | `terraform fmt`, `terraform validate` (no backend) | CI `ci.yml` | Written; (provider registry unreachable from the build sandbox) |
| Policy | tfsec, checkov, trivy fs | CI `security.yml` | Written, not yet run |
| Secrets | gitleaks | CI | Written, not yet run |
| Unit | Lambda handlers with mocked boto3 (`tests/`) | CI `ci.yml` | 6 tests pass locally |
| Plan review | `scripts/tf.sh dev plan` against the Landing Zone | Manual | Pending |
| Integration | Upload a test `.mp4`; expect `READY` item, HLS in processed bucket, 200 via CloudFront | Manual | Pending |
| DR drill | Block primary origin; confirm CloudFront serves the replica; Aurora switchover | Manual, semi-annual | Pending |

Known limits: the Step Functions definition and IAM policies have no automated test; MediaConvert job settings are checked only structurally.
