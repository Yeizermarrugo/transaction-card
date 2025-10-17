data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${aws_s3_bucket.transactions_report.arn}/*"
    ]
  }
}

data "aws_iam_policy_document" "lambda_policy_full" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      aws_dynamodb_table.card_table.arn,
      "${aws_dynamodb_table.card_table.arn}/index/user_id-index",
      aws_dynamodb_table.transaction_table.arn,
      "${aws_dynamodb_table.transaction_table.arn}/index/cardId-index",
      aws_dynamodb_table.card_table_error.arn
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl"
    ]
    resources = [
      aws_sqs_queue.create_request_card.arn,
      aws_sqs_queue.error_create_request_card.arn,
      aws_sqs_queue.start_payment.arn,
      aws_sqs_queue.check_balance.arn,
      aws_sqs_queue.transaction.arn
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${aws_s3_bucket.transactions_report.arn}/*",
      "${aws_s3_bucket.catalog_bucket.arn}/*"
    ]
  }
}

data "aws_iam_policy_document" "cache_access" {
  statement {
    effect = "Allow"
    actions = [
      "elasticache:DescribeCacheClusters",
      "elasticache:ListTagsForResource",
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs"
    ]
    resources = ["*"]
  }
}
