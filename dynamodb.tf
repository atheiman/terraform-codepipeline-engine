resource "aws_dynamodb_table" "tf_state_lock" {
  name         = "${var.resources_name}-terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
