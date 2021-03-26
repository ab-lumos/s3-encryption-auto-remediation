variable "shared_credentials_file" {
    type = string
    description = "Location of credentials file"
    default = "~/.aws/credentials"
}

variable "region" {
    type = string
    description = "AWS Region where infra is to be deployed"
    default = "us-west-2"
}

variable "profile" {
    type = string
    description = "AWS profile to be used"
    default = "test"
}

variable "cw_event_rule" {
    type = string
    description = "The name of the CoudWatch Event rule"
    default = "cw_rule_s3_encryption_auto_remediation"
}

variable "lambda_role" {
    type = string
    description = "The name of the AWS role for Lambda function to check and encrypt S3 buckets automatically"
    default = "role_s3_encryption_auto_remediation"
}

variable "lambda_policy" {
    type = string
    description = "The name of AWS IAM policy for Lambda function to check and encrypt S3 buckets automatically"
    default = "policy_s3_encryption_auto_remediation"
}

variable "lambda_function" {
    type = string
    description = "The name of the Lambda function that powers the compute of remediation activities"
    default = "lambda_s3_encryption_auto_remediation"
}

variable "exception_table_name" {
    type = string
    description = "The name of the DynamoDB Exception table"
    default = "exception_table_s3_encryption_auto_remediation"
}

variable "exception_s3_item" {
  type    = map
}

variable "record_action_table_name" {
    type = string
    description = "The name of the DynamoDB Exception table"
    default = "record_action_table_s3_encryption_auto_remediation"
}