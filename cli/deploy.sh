#!/usr/bin/env bash
# Deploys (or updates) the pipeline stack.
# Usage: ./cli/deploy.sh <github-username> <github-repo> <approval-email> [branch]
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <github-username> <github-repo> <approval-email> [branch]" >&2
  exit 1
fi

STACK="${STACK:-seis616-pipeline}"
cd "$(dirname "$0")/.."

echo "Deploying stack '$STACK' (repo: $1/$2, branch: ${4:-main}, reviewer: $3)..."
aws cloudformation deploy \
  --stack-name "$STACK" \
  --template-file pipeline.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    GitHubUsername="$1" \
    GitHubRepositoryName="$2" \
    ApprovalEmail="$3" \
    GitHubBranchName="${4:-main}"

aws cloudformation describe-stacks --stack-name "$STACK" \
  --query "Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}" --output table

cat <<EOF

Two one-time manual steps:
  1. Activate the GitHub connection:
     Console > Developer Tools > Settings > Connections > select '${STACK}-gh'
     > "Update pending connection" > install/authorize the AWS Connector for GitHub app.
  2. Confirm the SNS subscription from the email sent to $3.

(The pipeline's first automatic run fails at Source until step 1 is done. That is expected.)
Then run ./cli/verify.sh and push a commit when it asks.
EOF
