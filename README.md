# SEIS 616 – Software Delivery Pipeline with a Manual Review Stage

This is the pipeline from the Change Management Pipelines class (**GitHub → CodeBuild → CodeDeploy**, deploying the `python-project` Flask app to an Auto Scaling group behind an Application Load Balancer), with a **manual Review stage** added.
After code is checked in, the pipeline pulls it and then **pauses at Review**. The maintainer is **notified by email (Amazon SNS)** with the commit ID and a link to the commit on GitHub. The pipeline **resumes only after the change is approved**. If the change is rejected, the release stops.

```
 git push ─► Source ─► Review (Manual Approval) ─► Build (CodeBuild) ─► Deploy (CodeDeploy) ─► ALB ─► 2 x EC2
                          │
                          └─► SNS email to maintainer ─► Approve / Reject (console or CLI)
```

## What was added for the assignment
All of it is in `pipeline.yaml`:
1. **`ApprovalTopic`**: an SNS topic with the maintainer's email subscribed.
2. **`Review` stage**: a `Manual` approval action placed between `Source` and `Build`.
   - `NotificationArn` points to the topic.
   - `CustomData` and `ExternalEntityLink` use the source action's variables (`#{SourceVariables.CommitId}`), so the email says exactly which commit to review and links to it.
3. **`sns:Publish`** permission on `CodePipelineServiceRole`.

## Changes from the class template (to run on AWS today)
| Class template | This repo | Why |
|---|---|---|
| GitHub v1 source action + personal access token + webhook | `CodeStarSourceConnection` with a GitHub connection | AWS no longer recommends the v1 GitHub action. The connection needs no token stored in the template. |
| `AWS::AutoScaling::LaunchConfiguration` | `AWS::EC2::LaunchTemplate` | AWS has retired launch configurations, and newer accounts can't create them. |
| Hard-coded AMI ID | Latest Ubuntu 22.04 AMI looked up from SSM | The old AMI ID is region-specific and out of date. The app's scripts use `apt`. |
| `runtime-versions: nodejs 14 / python 3.9` in `buildspec.yml` | Image defaults (`aws/codebuild/standard:7.0`) | Those runtimes aren't offered on current CodeBuild images. |
| Flask 2.0.3, pytest 6 | Flask 3.0.3, pytest 8 | Flask 2.0.x breaks with current Werkzeug releases (`url_quote` import error). |
| `isExistApp = \`pgrep …\`` in the server scripts | `isExistApp=$(pgrep …)` | With spaces around `=`, the variable was never set, so the old server was never stopped and redeploys kept serving the old version. |
| `pip3 install` system-wide | Virtualenv in `/opt/python-venv` | On Ubuntu 22.04, pip can't replace the OS-managed `blinker` package that Flask needs. |
| Target group deregistration delay 300 s | 30 s | Each server in a OneAtATime deployment no longer waits 5 minutes. |

## Repository layout
| Path | Purpose |
|---|---|
| `pipeline.yaml` | CloudFormation template: network, ALB, ASG, CodeBuild, CodeDeploy, GitHub connection, **SNS topic**, **pipeline with Review stage** |
| `app.py`, `templates/`, `styles.less`, `tests/`, `requirements.txt` | The class `python-project` Flask app |
| `buildspec.yml` | CodeBuild: run unit tests, compile the LESS stylesheet |
| `appspec.yml`, `scripts/` | CodeDeploy: copy the app to `/opt/python-app`, install dependencies, stop and start the server |
| `cli/deploy.sh` | Creates or updates the stack |
| `cli/verify.sh` | End-to-end verification; writes `verification-output.txt` |
| `cli/teardown.sh` | Deletes everything |

## 1. Deploy
Prerequisites: AWS CLI v2 configured, and this repository pushed to GitHub on branch `main`.
```bash
./cli/deploy.sh <github-username> <repo-name> <your-email>
```
Then two one-time steps:
1. **Activate the GitHub connection.** Go to Console → Developer Tools → Settings → Connections, select `seis616-pipeline-gh`, click **Update pending connection**, and install or authorize the AWS Connector for GitHub app for this repo.
2. **Confirm the SNS subscription** from the "AWS Notification – Subscription Confirmation" email.

The first automatic pipeline run fails at Source until the connection is active. That's expected.

## 2. Verify
```bash
./cli/verify.sh
```
The script:
1. Checks the stack, the connection, the email subscription, and the stage layout.
2. Asks you to **push a commit**, for example by changing `Version 1.0` to `Version 1.1` in `templates/index.html`.
3. Waits until the pipeline is **paused at Review** and shows that Build and Deploy haven't run.
4. **Approves through the CLI** (`put-approval-result`).
5. Shows Build and Deploy succeeding and the website serving the new version.

Everything is saved to `verification-output.txt`.

To approve or reject in the browser instead: open the pipeline in the console, click **Review** on the Review stage, then choose **Approve** or **Reject**.

To show a rejection from the CLI:
```bash
P=seis616-pipeline-pipeline
TOKEN=$(aws codepipeline get-pipeline-state --name $P \
  --query "stageStates[?stageName=='Review'].actionStates[0].latestExecution.token | [0]" --output text)
aws codepipeline put-approval-result --pipeline-name $P --stage-name Review \
  --action-name ManualApproval --result "summary=Changes rejected,status=Rejected" --token "$TOKEN"
```

## 3. Tear down
```bash
./cli/teardown.sh
```
This empties the artifact bucket, deletes the stack (every resource above, including the EC2 instances, ALB, and VPC), and deletes the CodeBuild log group.
The ALB and EC2 instances cost money by the hour, so run this as soon as you have your outputs.
