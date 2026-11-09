# Verification Report – Manual Review Stage in CodePipeline

**Name:** _[your name]_  **Course:** SEIS 616 AI-Driven Cloud Infrastructure  **Date:** _[date]_
**Repository:** _[https://github.com/<username>/<repo>]_

## 1. Implementation
I extended the pipeline from class with a **Review** stage between Source and Build. The class pipeline runs GitHub → CodeBuild → CodeDeploy to an Auto Scaling group behind an ALB.

The Review stage contains a CodePipeline `Manual` approval action that publishes to an Amazon SNS topic. The maintainer's email is subscribed to that topic. When code is pushed to `main`, the pipeline pulls the commit and pauses at Review. The maintainer receives an email with the commit ID and a link to the commit. Build and Deploy run only after the change is approved. If the change is rejected, the execution stops.

Changes to the template:
- `ApprovalTopic` (`AWS::SNS::Topic`) with an email subscription
- `Review` stage with the `ManualApproval` action (`NotificationArn`, `CustomData`, `ExternalEntityLink`)
- `sns:Publish` added to the pipeline service role

I also updated parts of the class template that no longer run on current AWS. These are listed in the README.

## 2. How I verified it
I verified the implementation with the **AWS CLI** (`cli/verify.sh`) and in the **browser** (CodePipeline console, my email, and the website).

1. Deployed the stack, activated the GitHub connection, and confirmed the SNS subscription.
2. Confirmed with the CLI that the connection was `AVAILABLE`, the email subscription was confirmed, and the stages were Source → Review → Build → Deploy.
3. Checked in a code change (`Version 1.0` → `Version 1.1` in `templates/index.html`) and pushed it to GitHub.
4. Confirmed the pipeline paused at Review (`InProgress`), Build and Deploy did not start, and the website did not change.
5. Received the "APPROVAL NEEDED" email for the commit.
6. Approved the change with `aws codepipeline put-approval-result`.
7. Confirmed the pipeline resumed, Build and Deploy succeeded, and the website served Version 1.1.

## 3. Outputs

### 3.1 Stack, GitHub connection, email subscription
```
[paste sections 1–3 of verification-output.txt]
```

### 3.2 Pipeline stages, including the Review configuration
```
[paste section 4]
```

### 3.3 After check-in: pipeline paused at Review
```
[paste section 5]
```
_[Screenshot: CodePipeline console with Review "Waiting for approval"]_

### 3.4 Maintainer notification
_[Screenshot: "APPROVAL NEEDED" email showing the commit ID and review link]_

### 3.5 Approval and resumed pipeline
```
[paste sections 6–7]
```
_[Screenshot: console with all four stages Succeeded]_

### 3.6 Deployed application
```
[paste section 8]
```
_[Screenshot: browser at http://<ELBEndpoint>/ showing Version 1.1]_

## 4. Resource cleanup
I ran `cli/teardown.sh`. It emptied the artifact bucket, deleted the CloudFormation stack and every resource in it, and deleted the CodeBuild log group. The output confirms that no stack or project instances remain.
```
[paste teardown output]
```
