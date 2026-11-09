#!/usr/bin/env bash
# Deletes every AWS resource created by this project.
# Usage: ./cli/teardown.sh
set -euo pipefail

STACK="${STACK:-seis616-pipeline}"
output() {
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
BUCKET="$(output ArtifactBucketName)"
BUILD_PROJECT="$(output BuildProjectName)"

echo "1/3 Emptying artifact bucket '$BUCKET' (CloudFormation cannot delete a non-empty bucket)..."
aws s3 rm "s3://$BUCKET" --recursive

echo "2/3 Deleting stack '$STACK' (pipeline, SNS topic, connection, CodeBuild, CodeDeploy, ALB, ASG, VPC, roles)..."
aws cloudformation delete-stack --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --stack-name "$STACK"

echo "3/3 Deleting CodeBuild log group..."
aws logs delete-log-group --log-group-name "/aws/codebuild/$BUILD_PROJECT" 2>/dev/null || echo "   (no log group found)"

echo
echo "Confirming the stack is gone:"
aws cloudformation describe-stacks --stack-name "$STACK" 2>&1 | tail -1 || true
echo "Confirming no project EC2 instances remain:"
aws ec2 describe-instances --filters "Name=tag:Name,Values=webapp" \
  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text
echo "Teardown complete."
