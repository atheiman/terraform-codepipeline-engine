locals {
  codepipeline_source_action_name = "Source"
}

resource "aws_iam_role" "codepipeline" {
  name_prefix = "${var.resources_name}-codepipeline-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.acct_id
          }
        }
      },
    ]
  })

  managed_policy_arns = []
}

resource "aws_iam_role_policy" "codepipeline" {
  role        = aws_iam_role.codepipeline.id
  name_prefix = "${var.resources_name}-"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:DeleteObject",
          "s3:Get*",
          "s3:List*",
          "s3:PutObject",
        ]
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*",
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:StopBuild",
        ]
        Resource = [
          aws_codebuild_project.terraform.arn,
        ]
      },
    ]
  })
}

resource "aws_codepipeline" "codepipeline" {
  name           = var.resources_name
  pipeline_type  = "V2"
  execution_mode = "PARALLEL"
  role_arn       = aws_iam_role.codepipeline.arn

  # Reference variables using: "#{variables.var_name}"
  dynamic "variable" {
    for_each = local.codebuild_env_vars
    iterator = env_var
    content {
      name          = env_var.key
      description   = env_var.value.description
      default_value = env_var.value.default
    }
  }

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }

  stage {
    name = "Source"

    # https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-S3.html
    action {
      name             = local.codepipeline_source_action_name
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["Source"]

      configuration = {
        S3Bucket                    = aws_s3_bucket.source.bucket
        S3ObjectKey                 = "[ ERROR: Start pipeline execution with SourceRevisionOverride S3_OBJECT_KEY specifying the zipped Terraform module S3 key in bucket ${aws_s3_bucket.source.bucket} - this option is only available using the CodePipeline StartPipelineExecution API / AWS CLI: `aws codepipeline start-pipeline-execution --source-revisions '[{\"actionName\":\"${local.codepipeline_source_action_name}\",\"revisionType\":\"S3_OBJECT_KEY\",\"revisionValue\":\"path/to/terraform-module.zip\"}]'` ]"
        AllowOverrideForS3ObjectKey = true
        PollForSourceChanges        = false
      }
    }
  }

  stage {
    name = "TerraformPlan"

    # https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-CodeBuild.html
    action {
      name             = "TerraformPlan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["Source"]
      output_artifacts = ["TerraformPlan"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.terraform.name
        EnvironmentVariables = jsonencode(concat(
          [
            {
              name  = "TERRAFORM_COMMAND"
              value = "plan"
            }
          ],
          [
            for k, env_var in local.codebuild_env_vars :
            {
              name  = k
              value = "#{variables.${k}}"
            }
          ],
        ))
      }
    }
  }

  stage {
    name = "Approval"

    # https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-CodeBuild.html
    action {
      name               = "Approval"
      category           = "Approval"
      owner              = "AWS"
      provider           = "Manual"
      version            = "1"
      timeout_in_minutes = var.codepipeline_approval_timeout_in_minutes

      configuration = {
        # NotificationArn = "arn:${local.partition}:sns:${local.region}:${local.acct_id}:MyApprovalTopic"
        # ExternalEntityLink = "http://example.com"
        CustomData = "Review Terraform plan output in CodePipeline console"
      }
    }
  }

  stage {
    name = "TerraformApply"

    # https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-CodeBuild.html
    action {
      name             = "TerraformApply"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["TerraformPlan"]
      output_artifacts = ["TerraformApply"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.terraform.name
        EnvironmentVariables = jsonencode(concat(
          [
            {
              name  = "TERRAFORM_COMMAND"
              value = "apply"
            }
          ],
          [
            for k, env_var in local.codebuild_env_vars :
            {
              name  = k
              value = "#{variables.${k}}"
            }
          ],
        ))
      }
    }
  }
}
