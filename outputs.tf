output "codebuild_service_role" {
  description = "CodeBuild service role. Custom Terraform execution roles specified in CodePipeline variable TERRAFORM_ROLE_ARN must be assumable by this role."
  value       = aws_iam_role.codebuild
}

output "default_terraform_execution_role" {
  description = "Default Terraform execution role. IAM policies can be attached to this role to allow Terraform to perform AWS actions, or Terraform execution role can be overridden in CodePipeline using variable TERRAFORM_ROLE_ARN."
  value       = aws_iam_role.terraform
}

output "codepipeline" {
  description = "CodePipeline pipeline for the Terraform engine"
  value       = aws_codepipeline.codepipeline
}

output "artifacts_bucket" {
  description = "Terraform outputs and other artifacts will be uploaded to this bucket."
  value       = aws_s3_bucket.artifacts
}

output "source_bucket" {
  description = "Upload Terraform modules to this bucket as .zip files. Terraform will be executed in the root of an unzipped Terraform module directory."
  value       = aws_s3_bucket.source
}

output "terraform_backend_bucket" {
  description = "S3 bucket available to be used for Terraform state."
  value       = aws_s3_bucket.tf_backend
}

output "aws_dynamodb_table_tf_state_lock" {
  description = "DynamoDB table available to be used for Terraform state locking."
  value       = aws_dynamodb_table.tf_state_lock
}

output "codepipeline_source_action_name" {
  description = "CodePipeline Source action name used in StartPipelineExecution API parameter sourceRevisions actionName."
  value       = local.codepipeline_source_action_name
}

output "example_aws_cli_start_pipeline_execution_command" {
  description = "AWS CLI command that will start CodePipeline execution with an uploaded zipped Terraform module."
  value       = "aws codepipeline start-pipeline-execution --name '${aws_codepipeline.codepipeline.name}' --source-revisions '[{\"actionName\":\"${local.codepipeline_source_action_name}\",\"revisionType\":\"S3_OBJECT_KEY\",\"revisionValue\":\"path/to/terraform-module.zip\"}]'\n"
}
