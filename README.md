# Terraform CodePipeline Engine

Terraform module to deploy an AWS CodePipeline and CodeBuild Terraform engine to plan and apply other Terraform modules. Basic workflow:

1. A user uploads a Terraform module as a zip package to the source S3 bucket created by this module (output `source_bucket`).
   Note: Terraform module zip packages must be uploaded to the source bucket created by this module. CodePipeline executions cannot start with overridden S3 bucket sources.
1. The user starts the CodePipeline pipeline (output `codepipeline`) using [CodePipeline API `StartPipelineExecution` with `sourceRevisions` parameter](https://docs.aws.amazon.com/codepipeline/latest/APIReference/API_StartPipelineExecution.html#API_StartPipelineExecution_RequestParameters) to specify the S3 object key of the uploaded Terraform module zip package.
   <br/>Note: As of Dec 2024, CodePipeline console does not support starting pipeline executions with source revision S3 key override, only S3 object version override. To override source revision S3 key, you must use the CodePipeline API. Here is an example [AWS CLI `aws codepipeline start-pipeline-execution` command](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/codepipeline/start-pipeline-execution.html) to specify a source revision S3 key override (output `example_aws_cli_start_pipeline_execution_command`):
   ```bash
   aws codepipeline start-pipeline-execution --name 'terraform-engine' --source-revisions '[{"actionName":"Source","revisionType":"S3_OBJECT_KEY","revisionValue":"path/to/terraform-module.zip"}]'
   ```
   Note: Additional pipeline variables can be specified to customize Terraform execution behavior. You can view these available variables by clicking `Edit` or `Release change` on the deployed pipeline.
1. CodePipeline downloads the Terraform module zip package from the `source_bucket`, then starts a CodeBuild project to plan the Terraform module. The plan and a plan summary are saved as artifacts in S3 (output `artifacts_bucket`).
1. CodePipeline waits for [Approval](https://docs.aws.amazon.com/codepipeline/latest/userguide/approvals.html) of the planned change. The user reviews the plan in the CodePipeline console, and approves the plan to be applied.
1. After approval, CodePipeline starts the CodeBuild project again. CodeBuild applies the planned change for the Terraform module.
