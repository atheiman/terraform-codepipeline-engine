terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

module "terraform_codepipeline_engine" {
  source = "../.."
}

# Allow the module default Terraform execution role to provision resources (SSM parameters). Alternative approach is to
# create a custom Terraform execution role, then run CodePipeline with variable TERRAFORM_ROLE_ARN to assume the role
# for Terraform execution.
resource "aws_iam_role_policy" "default_terraform_execution_role" {
  role        = module.terraform_codepipeline_engine.default_terraform_execution_role.id
  name_prefix = "terraform-provisioning-"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:*Parameter*",
          "ssm:*Tags*",
        ]
        Resource = "*"
      },
    ]
  })
}

# A simple example Terraform module
data "archive_file" "tf_module_ssm_parameter" {
  type        = "zip"
  output_path = "${path.root}/terraform-module-ssm-parameter.zip"

  source {
    filename = "main.tf"
    content  = <<-EOF
      terraform {
        required_providers {
          aws = {
            source  = "hashicorp/aws"
            version = ">= 5.0"
          }
        }

        backend "s3" {
          # The module provides an S3 backend state storage bucket, or a custom bucket can be specified
          bucket = "${module.terraform_codepipeline_engine.terraform_backend_bucket.bucket}"
          # Be sure to specify a different key for each Terraform module
          key = "my-team/ssm-parameter-module.tfstate"
          # The module provides a DynamoDB table for state locking (optional)
          dynamodb_table = "${module.terraform_codepipeline_engine.aws_dynamodb_table_tf_state_lock.name}"
        }
      }

      resource "aws_ssm_parameter" "example" {
        type  = "String"
        name  = "/example/created-by-terraform"
        value = "This ssm parameter was created by Terraform CodePipeline pipeline '${module.terraform_codepipeline_engine.codepipeline.arn}'"
      }

      output "ssm_parameter_arn" {
        value = aws_ssm_parameter.example.arn
      }
    EOF
  }
}

# Terraform modules are uploaded to the source bucket provided by the module
resource "aws_s3_object" "tf_module_ssm_parameter" {
  bucket = module.terraform_codepipeline_engine.source_bucket.bucket
  key    = "my-team/${reverse(split("/", data.archive_file.tf_module_ssm_parameter.output_path))[0]}"
  source = data.archive_file.tf_module_ssm_parameter.output_path
  etag   = filemd5(data.archive_file.tf_module_ssm_parameter.output_path)
}

# AWS CLI command to start the CodePipeline execution
output "aws_cli_start_pipeline_execution_command" {
  description = "AWS CLI command that will start CodePipeline execution with the uploaded example Terraform module."
  value       = "aws codepipeline start-pipeline-execution --name '${module.terraform_codepipeline_engine.codepipeline.name}' --source-revisions '[{\"actionName\":\"${module.terraform_codepipeline_engine.codepipeline_source_action_name}\",\"revisionType\":\"S3_OBJECT_KEY\",\"revisionValue\":\"${aws_s3_object.tf_module_ssm_parameter.key}\"}]'\n"
}
