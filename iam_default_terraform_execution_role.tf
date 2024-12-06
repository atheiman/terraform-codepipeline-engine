resource "aws_iam_role" "terraform" {
  name_prefix = "${var.resources_name}-terraform-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          AWS = aws_iam_role.codebuild.arn
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "terraform" {
  role        = aws_iam_role.terraform.id
  name_prefix = "${var.resources_name}-"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # https://developer.hashicorp.com/terraform/language/backend/s3#permissions-required
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
        ]
        Resource = [
          aws_s3_bucket.tf_backend.arn,
          "${aws_s3_bucket.tf_backend.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = [
          aws_dynamodb_table.tf_state_lock.arn,
        ]
      },
    ]
  })
}
