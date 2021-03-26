provider "aws" {
  shared_credentials_file = var.shared_credentials_file
  region                  = var.region
  profile                 = var.profile
}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_event_rule" "s3_event_notification" {
  name        = var.cw_event_rule
  description = "Capture S3 bucket actions like creation of bucket or update of Properties for auto enablement of S3 encryption"

  event_pattern = <<PATTERN
{
  "source": [
    "aws.s3"
  ],
  "detail-type": [
    "AWS API Call via CloudTrail"
  ],
  "detail": {
    "eventSource": [
      "s3.amazonaws.com"
    ],
    "eventName": [
      "CreateBucket"
    ]
  }
}
PATTERN
}

resource "aws_cloudwatch_event_target" "lambda_encryption" {
  rule      = aws_cloudwatch_event_rule.s3_event_notification.name
  target_id = "SendToLambdaForEncryption"
  arn       = aws_lambda_function.lambda_s3_encryption_auto_remediation.arn
}

resource "aws_kms_key" "default_key_s3_encryption_auto_remediation" {
  description             = "KMS key for default encryption of S3 bucket by auto remediating Lambda function"
  enable_key_rotation = "true"
}

resource "aws_kms_key" "key_encryption_infra" {
  description             = "KMS key for encryption of DynamoDBs created as part of this infra and Lambda environment variables"
  enable_key_rotation = "true"
}

resource "aws_iam_role" "role_s3_encryption_auto_remediation" {
  name = var.lambda_role
  description = "AWS role for Lambda function to check and encrypt S3 buckets automatically"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

resource "aws_iam_policy" "policy_s3_encryption_auto_remediation" {
  name        = var.lambda_policy
  description = "AWS IAM policy for Lambda function to check and encrypt S3 buckets automatically"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:PutEncryptionConfiguration",
                "s3:GetEncryptionConfiguration",
                "logs:CreateLogDelivery",
                "logs:CreateLogStream",
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "kms:GetKeyRotationStatus",
                "kms:EnableKeyRotation",
                "logs:CreateLogGroup",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "attach_s3_encryption_auto_remediation" {
  role       = aws_iam_role.role_s3_encryption_auto_remediation.name
  policy_arn = aws_iam_policy.policy_s3_encryption_auto_remediation.arn
}

resource "aws_lambda_function" "lambda_s3_encryption_auto_remediation" {
  filename      = "lambda_function_payload.zip"
  function_name = var.lambda_function
  role          = aws_iam_role.role_s3_encryption_auto_remediation.arn
  handler       = "lambda_function.lambda_handler"

  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  runtime = "python3.8"

  kms_key_arn = aws_kms_key.key_encryption_infra.arn

  environment {
    variables = {
      ExceptionTableName = aws_dynamodb_table.dynamodb_exception.name,
      KmsKeyID = aws_kms_key.default_key_s3_encryption_auto_remediation.key_id,
      RecordingTableName = aws_dynamodb_table.dynamodb_record_action.name
    }
  }
}

resource "aws_dynamodb_table" "dynamodb_exception" {
  name           = var.exception_table_name
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "ResourceName"

  attribute {
    name = "ResourceName"
    type = "S"
  }

}
    
resource "aws_dynamodb_table_item" "exception_to_be_added" {

  for_each = var.exception_s3_item

  table_name = aws_dynamodb_table.dynamodb_exception.name
  hash_key   = aws_dynamodb_table.dynamodb_exception.hash_key

  item = <<ITEM
  {
    "ResourceName": {"S": "${each.key}"},
    "expiry": {"S": "${each.value}"}
  }
  ITEM

}

resource "aws_dynamodb_table" "dynamodb_record_action" {
  name           = var.record_action_table_name
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "ResourceName"
  range_key      = "Timestamp"

  attribute {
    name = "ResourceName"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "S"
  }

  server_side_encryption {
    enabled = "true"
    kms_key_arn = aws_kms_key.key_encryption_infra.arn
  }

}