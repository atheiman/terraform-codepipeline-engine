variable "resources_name" {
  description = "Name for created resources, sometimes used as a prefix"
  type        = string
  default     = "terraform-engine"
}

variable "codepipeline_approval_timeout_in_minutes" {
  description = "CodePipeline approval timeout in minutes"
  type        = number
  default     = 2880
}
