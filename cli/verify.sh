#!/usr/bin/env bash
# Verifies the manual Review stage end to end and saves all output to verification-output.txt.
# Usage: ./cli/verify.sh
set -euo pipefail

STACK="${STACK:-seis616-pipeline}"
cd "$(dirname "$0")/.."
OUT="verification-output.txt"
: > "$OUT"

run() {   # print a command and its output to screen + file
  echo "\$ $*" | tee -a "$OUT"
  "$@" 2>&1 | tee -a "$OUT" || true
  echo | tee -a "$OUT"
}
section() { printf '\n==== %s ====\n' "$1" | tee -a "$OUT"; }
output() {
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
stage_field() {   # stage_field <stage> <jmespath under latestExecution>
  aws codepipeline get-pipeline-state --name "$PIPELINE" \
    --query "stageStates[?stageName=='$1'].$2 | [0]" --output text
}

PIPELINE="$(output PipelineName)"
CONNECTION="$(output ConnectionArn)"
TOPIC="$(output ApprovalTopicArn)"
ELB="$(output ELBEndpoint)"
CD_APP="$(output CodeDeployApplication)"
CD_GROUP="$(output CodeDeployDeploymentGroup)"

echo "Verification run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" | tee -a "$OUT"

section "1. Pipeline stack deployed"
run aws cloudformation describe-stacks --stack-name "$STACK" \
  --query "Stacks[0].{Stack:StackName,Status:StackStatus}" --output table

section "2. GitHub connection is AVAILABLE"
run aws codestar-connections get-connection --connection-arn "$CONNECTION" \
  --query "Connection.{Name:ConnectionName,Status:ConnectionStatus,Provider:ProviderType}" --output table

section "3. Maintainer is subscribed to the approval topic"
run aws sns list-subscriptions-by-topic --topic-arn "$TOPIC" \
  --query "Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint,SubscriptionArn:SubscriptionArn}" --output table

section "4. Pipeline structure: Source -> Review -> Build -> Deploy"
run aws codepipeline get-pipeline --name "$PIPELINE" \
  --query "pipeline.stages[].{Stage:name,Action:actions[0].name,Category:actions[0].actionTypeId.category,Provider:actions[0].actionTypeId.provider}" --output table
run aws codepipeline get-pipeline --name "$PIPELINE" \
  --query "pipeline.stages[?name=='Review'].actions[0].configuration" --output json

section "5. Check in code; pipeline pauses at Review"
echo ">>> Push a commit to GitHub now (e.g. change 'Version 1.0' in templates/index.html)."
echo ">>> Waiting for the Review stage to start (up to 10 minutes)..."
for _ in $(seq 1 60); do
  [[ "$(stage_field Review latestExecution.status)" == "InProgress" ]] && break
  sleep 10
done
if [[ "$(stage_field Review latestExecution.status)" != "InProgress" ]]; then
  echo "Review stage never started. Check the Source stage in the console." | tee -a "$OUT"
  exit 1
fi
EXEC_ID="$(stage_field Review latestExecution.pipelineExecutionId)"

echo "Execution $EXEC_ID is paused at Review. Build and Deploy have not run for it:" | tee -a "$OUT"
run aws codepipeline get-pipeline-state --name "$PIPELINE" \
  --query "stageStates[].{Stage:stageName,Status:latestExecution.status,ExecutionId:latestExecution.pipelineExecutionId}" --output table
run aws codepipeline get-pipeline-execution --pipeline-name "$PIPELINE" --pipeline-execution-id "$EXEC_ID" \
  --query "pipelineExecution.{Status:status,Commit:artifactRevisions[0].revisionId,Message:artifactRevisions[0].revisionSummary}" --output table
echo "Website while the change waits for review (still the previous version, or 502/503 if nothing has been deployed yet):" | tee -a "$OUT"
run curl -s -w "\nHTTP %{http_code}\n" "http://$ELB/"

echo ">>> Check your inbox for the 'APPROVAL NEEDED' email and screenshot it for the report."
read -r -p ">>> Press Enter to approve the change from the CLI..."

section "6. Maintainer approves the change"
TOKEN="$(stage_field Review "actionStates[0].latestExecution.token")"
run aws codepipeline put-approval-result \
  --pipeline-name "$PIPELINE" \
  --stage-name Review \
  --action-name ManualApproval \
  --result "summary=Reviewed and approved via CLI,status=Approved" \
  --token "$TOKEN"

section "7. Pipeline resumes: Build and Deploy run"
echo "Waiting for Build and Deploy to finish (CodeDeploy updates one server at a time; ~5-10 minutes)..."
for _ in $(seq 1 120); do
  STATUS="$(aws codepipeline get-pipeline-execution --pipeline-name "$PIPELINE" \
    --pipeline-execution-id "$EXEC_ID" --query "pipelineExecution.status" --output text)"
  [[ "$STATUS" != "InProgress" ]] && break
  sleep 15
done
run aws codepipeline get-pipeline-state --name "$PIPELINE" \
  --query "stageStates[].{Stage:stageName,Status:latestExecution.status}" --output table
run aws codepipeline list-action-executions --pipeline-name "$PIPELINE" \
  --filter "pipelineExecutionId=$EXEC_ID" \
  --query "actionExecutionDetails[].{Stage:stageName,Action:actionName,Status:status,Summary:output.executionResult.externalExecutionSummary}" \
  --output table

section "8. CodeDeploy deployment and live website"
DEPLOYMENT="$(aws deploy list-deployments --application-name "$CD_APP" --deployment-group-name "$CD_GROUP" \
  --query "deployments[0]" --output text)"
run aws deploy get-deployment --deployment-id "$DEPLOYMENT" \
  --query "deploymentInfo.{Id:deploymentId,Status:status,Creator:creator,Overview:deploymentOverview}" --output json
echo "Website after approval and deployment:" | tee -a "$OUT"
run curl -s -w "\nHTTP %{http_code}\n" "http://$ELB/"

echo "Done. Full output saved to $OUT. Open http://$ELB/ in a browser for a screenshot."
