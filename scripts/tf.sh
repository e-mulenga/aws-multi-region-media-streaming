#!/usr/bin/env bash
# Runs OpenTofu/Terraform for the root stack in one environment.
# Usage: scripts/tf.sh <dev|stage|prod> <init|plan|apply|destroy|output|...> [args]
# State lives in the Landing Zone state bucket named in environments/<env>/backend.hcl (git-ignored).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV="${1:?env: dev|stage|prod}"
CMD="${2:?command}"
shift 2

TF="${TF_BIN:-$(command -v tofu || command -v terraform)}"
DIR="$ROOT"
ENVDIR="$ROOT/environments/$ENV"
[ -f "$ENVDIR/backend.hcl" ] || { echo "missing $ENVDIR/backend.hcl (copy backend.hcl.example)" >&2; exit 2; }
[ -f "$ENVDIR/terraform.tfvars" ] || { echo "missing $ENVDIR/terraform.tfvars (copy terraform.tfvars.example)" >&2; exit 2; }

case "$CMD" in
  init)
    exec "$TF" -chdir="$DIR" init -reconfigure -backend-config="$ENVDIR/backend.hcl" \
      -backend-config="key=aws-multi-region-media-streaming/$ENV.tfstate" "$@" ;;
  plan|apply|destroy|import|refresh)
    exec "$TF" -chdir="$DIR" "$CMD" -var-file="$ENVDIR/terraform.tfvars" "$@" ;;
  *)
    exec "$TF" -chdir="$DIR" "$CMD" "$@" ;;
esac
