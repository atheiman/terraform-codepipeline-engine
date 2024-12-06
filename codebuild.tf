locals {
  # Environment variables that can be passed to CodeBuild to customize Terraform execution
  codebuild_env_vars = {
    TERRAFORM_ROLE_ARN = {
      description = "Terraform execution role arn. Used for all terraform commands during CodeBuild jobs."
      default     = aws_iam_role.terraform.arn
    }
    TERRAFORM_VERSION = {
      description = "Terraform version"
      default     = "1.9.8"
    }
    # CodePipeline does not allow empty variable arguments, so whitespace can be used to make these variables not take any effect.
    TF_CLI_ARGS = {
      description = "Additional arguments for all Terraform commands. Input whitespace (a single space character) to omit this variable."
      default     = "-no-color"
    }
    TF_CLI_ARGS_init = {
      description = "Additional arguments for Terraform 'init' command. Input whitespace (a single space character) to omit this variable."
      default     = " "
    }
    TF_CLI_ARGS_plan = {
      description = "Additional arguments for Terraform 'plan' command. Input whitespace (a single space character) to omit this variable."
      default     = " "
    }
    TF_CLI_ARGS_apply = {
      description = "Additional arguments for Terraform 'apply' command. Input whitespace (a single space character) to omit this variable."
      default     = " "
    }
    DEBUG = {
      description = "Set to any value other than 'false' to enable Bash debug"
      default     = "true"
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name_prefix = "${var.resources_name}-codebuild-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "codebuild.amazonaws.com"
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

resource "aws_iam_role_policy" "codebuild" {
  role        = aws_iam_role.codebuild.id
  name_prefix = "${var.resources_name}-"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.codebuild.arn}:log-stream:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.resources_name}"
  retention_in_days = 14
}

resource "aws_codebuild_project" "terraform" {
  name          = var.resources_name
  description   = "Terraform engine"
  build_timeout = 60 # minutes
  service_role  = aws_iam_role.codebuild.arn

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    dynamic "environment_variable" {
      for_each = local.codebuild_env_vars
      content {
        name  = environment_variable.key
        value = environment_variable.value.default
      }
    }

    environment_variable {
      name  = "TF_IN_AUTOMATION"
      value = "true"
    }
    environment_variable {
      name  = "TF_INPUT"
      value = "false"
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-EOF
      version: 0.2

      artifacts:
        files:
          - '**/*'
        exclude-paths:
          - '.terraform/**/*'

      phases:
        build:
          commands:
          - |
              set -eu
              if [[ "$DEBUG" != 'false' ]]; then set -x; fi
              env | sort

              # Show CodeBuild service role
              aws sts get-caller-identity

              # Show downloaded unzipped Terraform module and any other files in current directory
              find . -type f

              # Configure AWS default profile to assume Terraform execution role
              aws configure set credential_source EcsContainer
              aws configure set role_arn "$TERRAFORM_ROLE_ARN"
              aws configure set role_session_name "codebuild-terraform-$${CODEBUILD_BUILD_NUMBER}"
              cat ~/.aws/config
              # Show Terraform execution role
              aws sts get-caller-identity

              # Ensure /usr/local/bin is at front of PATH for installed tools
              mkdir -p /usr/local/bin
              export PATH="/usr/local/bin:$PATH"

              # Install terraform
              curl -Lso /tmp/terraform.zip "https://releases.hashicorp.com/terraform/$${TERRAFORM_VERSION}/terraform_$${TERRAFORM_VERSION}_linux_amd64.zip"
              unzip /tmp/terraform.zip terraform -d /usr/local/bin
              chmod +x /usr/local/bin/terraform
              terraform -version

              # Install tf-summarize
              curl -Lso /tmp/tf-summarize.tar.gz "https://github.com/dineshba/tf-summarize/releases/download/v0.3.14/tf-summarize_linux_amd64.tar.gz"
              tar -x -C /usr/local/bin -f /tmp/tf-summarize.tar.gz tf-summarize
              chmod +x /usr/local/bin/tf-summarize
              tf-summarize -v

              # Run terraform commands
              terraform init
              if [[ "$TERRAFORM_COMMAND" == 'plan' ]]; then
                terraform plan -out tfplan.binary
                terraform show tfplan.binary > tfplan.txt
                terraform show -json tfplan.binary > tfplan.json
                cat tfplan.json | tf-summarize -md | tee tfplan.summary.md
              elif [[ "$TERRAFORM_COMMAND" == 'apply' ]]; then
                cat tfplan.txt
                cat tfplan.summary.md
                terraform apply tfplan.binary
                terraform output -json | tee outputs.json
              fi
    EOF
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  # cache {
  #   type     = "S3"
  #   location = aws_s3_bucket.example.bucket
  # }

  # vpc_config {
  #   vpc_id = aws_vpc.example.id

  #   subnets = [
  #     aws_subnet.example1.id,
  #     aws_subnet.example2.id,
  #   ]

  #   security_group_ids = [
  #     aws_security_group.example1.id,
  #     aws_security_group.example2.id,
  #   ]
  # }
}
