# DynamoDB Tables
resource "aws_dynamodb_table" "card_table" {
  name         = "card-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "uuid"
  range_key    = "createdAt"
  attribute {
    name = "uuid"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "S"
  }

  attribute {
  name = "user_id"
  type = "S"
}

global_secondary_index {
  name               = "user_id-index"
  hash_key           = "user_id"
  projection_type    = "ALL"
}
}

resource "aws_dynamodb_table" "transaction_table" {
  name         = "transaction-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "uuid"
  range_key    = "createdAt"
  attribute {
    name = "uuid"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "S"
  }

attribute {
  name = "cardId"
  type = "S"
}

global_secondary_index {
  name               = "cardId-index"
  hash_key           = "cardId"
  projection_type    = "ALL"
}
}

resource "aws_dynamodb_table" "card_table_error" {
  name         = "card-table-error"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "uuid"
  range_key    = "createdAt"
  attribute {
    name = "uuid"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "S"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "transactions_report" {
  bucket = var.transactions_report_bucket
  acl    = "private"
}

# SQS Queues
resource "aws_sqs_queue" "create_request_card" {
  name = "create-request-card-sqs"
}

resource "aws_sqs_queue" "error_create_request_card" {
  name = "error-create-request-card-sqs"
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec" {
  name               = "ExecutionLambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_policy" "lambda_policy_full" {
  name   = "LambdaFullAccessCardService"
  policy = data.aws_iam_policy_document.lambda_policy_full.json
}

resource "aws_iam_role_policy_attachment" "lambda_full_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy_full.arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -----------Lambda Function---------------
#############################
# LAMBDA FUNCTIONS
#############################

locals {
  lambda_env_vars = {
    CARD_TABLE_NAME        = aws_dynamodb_table.card_table.name
    TRANSACTION_TABLE_NAME = aws_dynamodb_table.transaction_table.name
    ERROR_TABLE_NAME       = aws_dynamodb_table.card_table_error.name
    SQS_URL                = aws_sqs_queue.create_request_card.id
    REPORT_BUCKET          = aws_s3_bucket.transactions_report.bucket
  }
}

resource "aws_lambda_function" "create_request_card_lambda" {
  filename         = "create-request-card-lambda.zip"
  function_name    = "create-request-card-lambda"
  handler          = "create-request-card.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("create-request-card-lambda.zip")
  environment {
    variables = local.lambda_env_vars
  }
}

resource "aws_lambda_function" "card_activate_lambda" {
  filename         = "card-activate-lambda.zip"
  function_name    = "card-activate-lambda"
  handler          = "card-activate.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("card-activate-lambda.zip")
  environment {
    variables = local.lambda_env_vars
  }
}

resource "aws_lambda_function" "card_purchase_lambda" {
  filename         = "card-purchase-lambda.zip"
  function_name    = "card-purchase-lambda"
  handler          = "card-purchase.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("card-purchase-lambda.zip")
  environment {
    variables = local.lambda_env_vars
  }
}

resource "aws_lambda_function" "card_transaction_lambda" {
  filename         = "card-transaction-lambda.zip"
  function_name    = "card-transaction-lambda"
  handler          = "card-transaction.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("card-transaction-lambda.zip")
  environment {
    variables = local.lambda_env_vars
  }
}

resource "aws_lambda_function" "card_paid_credit_card_lambda" {
  filename         = "card-paid-credit-card-lambda.zip"
  function_name    = "card-paid-credit-card-lambda"
  handler          = "card-paid-credit-card.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("card-paid-credit-card-lambda.zip")
  environment {
    variables = local.lambda_env_vars
  }
}

resource "aws_lambda_function" "card_get_report_lambda" {
  filename         = "card-get-report-lambda.zip"
  function_name    = "card-get-report-lambda"
  handler          = "card-get-report.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("card-get-report-lambda.zip")
  environment {
    variables = local.lambda_env_vars
  }
}

# Event Source Mapping SQS -> Lambda
resource "aws_lambda_event_source_mapping" "create_request_card_sqs" {
  event_source_arn = aws_sqs_queue.create_request_card.arn
  function_name    = aws_lambda_function.create_request_card_lambda.arn
  batch_size       = 1
}

resource "aws_lambda_event_source_mapping" "card_activate_sqs" {
  event_source_arn = aws_sqs_queue.create_request_card.arn
  function_name    = aws_lambda_function.card_activate_lambda.arn
  batch_size       = 1
}

resource "aws_lambda_event_source_mapping" "card_purchase_sqs" {
  event_source_arn = aws_sqs_queue.create_request_card.arn
  function_name    = aws_lambda_function.card_purchase_lambda.arn
  batch_size       = 1
}

resource "aws_lambda_event_source_mapping" "card_transaction_sqs" {
  event_source_arn = aws_sqs_queue.create_request_card.arn
  function_name    = aws_lambda_function.card_transaction_lambda.arn
  batch_size       = 1
}

resource "aws_lambda_event_source_mapping" "card_paid_credit_card_sqs" {
  event_source_arn = aws_sqs_queue.create_request_card.arn
  function_name    = aws_lambda_function.card_paid_credit_card_lambda.arn
  batch_size       = 1
}

resource "aws_lambda_event_source_mapping" "card_get_report_sqs" {
  event_source_arn = aws_sqs_queue.create_request_card.arn
  function_name    = aws_lambda_function.card_get_report_lambda.arn
  batch_size       = 1
}



# API Gateway (simplificado)
#############################
# API Gateway: CardServiceAPI
#############################

resource "aws_api_gateway_rest_api" "card_api" {
  name = "CardServiceAPI"
}

# Raíz: /card
resource "aws_api_gateway_resource" "card" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_rest_api.card_api.root_resource_id
  path_part   = "card"
}

# /card/create
resource "aws_api_gateway_resource" "card_create" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.card.id
  path_part   = "create"
}

resource "aws_api_gateway_method" "card_create_post" {
  rest_api_id   = aws_api_gateway_rest_api.card_api.id
  resource_id   = aws_api_gateway_resource.card_create.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "card_create_post_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.card_api.id
  resource_id             = aws_api_gateway_resource.card_create.id
  http_method             = aws_api_gateway_method.card_create_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.create_request_card_lambda.invoke_arn
}

resource "aws_lambda_permission" "allow_api_gateway_card_create" {
  statement_id  = "AllowAPIGatewayInvokeCardCreate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_request_card_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.card_api.execution_arn}/*/POST/card/create"
}

# /card/activate
resource "aws_api_gateway_resource" "card_activate" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.card.id
  path_part   = "activate"
}

resource "aws_api_gateway_method" "card_activate_post" {
  rest_api_id   = aws_api_gateway_rest_api.card_api.id
  resource_id   = aws_api_gateway_resource.card_activate.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "card_activate_post_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.card_api.id
  resource_id             = aws_api_gateway_resource.card_activate.id
  http_method             = aws_api_gateway_method.card_activate_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.card_activate_lambda.invoke_arn
}


resource "aws_lambda_permission" "allow_api_gateway_card_activate" {
  statement_id  = "AllowAPIGatewayInvokeCardActivate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.card_activate_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.card_api.execution_arn}/*/POST/card/activate"
}

// /card/purchase
resource "aws_api_gateway_resource" "card_purchase" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.card.id
  path_part   = "purchase"
}

resource "aws_api_gateway_method" "card_purchase_post" {
  rest_api_id   = aws_api_gateway_rest_api.card_api.id
  resource_id   = aws_api_gateway_resource.card_purchase.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "card_purchase_post_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.card_api.id
  resource_id             = aws_api_gateway_resource.card_purchase.id
  http_method             = aws_api_gateway_method.card_purchase_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.card_purchase_lambda.invoke_arn
}

resource "aws_lambda_permission" "allow_api_gateway_card_purchase" {
  statement_id  = "AllowAPIGatewayInvokeCardPurchase"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.card_purchase_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.card_api.execution_arn}/*/POST/card/purchase"
}

// /card/transaction
resource "aws_api_gateway_resource" "card_transaction" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.card.id
  path_part   = "transaction"
}

resource "aws_api_gateway_resource" "card_transaction_id" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.card_transaction.id
  path_part   = "{cardId}"
}

resource "aws_api_gateway_method" "card_transaction_post" {
  rest_api_id   = aws_api_gateway_rest_api.card_api.id
  resource_id   = aws_api_gateway_resource.card_transaction_id.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "card_transaction_post_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.card_api.id
  resource_id             = aws_api_gateway_resource.card_transaction_id.id
  http_method             = aws_api_gateway_method.card_transaction_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.card_transaction_lambda.invoke_arn
}

resource "aws_lambda_permission" "allow_api_gateway_card_transaction" {
  statement_id  = "AllowAPIGatewayInvokeCardTransaction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.card_transaction_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.card_api.execution_arn}/*/POST/card/transaction/*"
}

// card/paid-credit-card

resource "aws_api_gateway_resource" "card_paid_credit_card" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.card.id
  path_part   = "paid-credit-card"
}


resource "aws_api_gateway_method" "card_paid_credit_card_post" {
  rest_api_id   = aws_api_gateway_rest_api.card_api.id
  resource_id   = aws_api_gateway_resource.card_paid_credit_card.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "card_paid_credit_card_post_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.card_api.id
  resource_id             = aws_api_gateway_resource.card_paid_credit_card.id
  http_method             = aws_api_gateway_method.card_paid_credit_card_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.card_paid_credit_card_lambda.invoke_arn
}

resource "aws_lambda_permission" "allow_api_gateway_card_paid_credit_card" {
  statement_id  = "AllowAPIGatewayInvokeCardPaidCreditCard"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.card_paid_credit_card_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.card_api.execution_arn}/*/POST/card/paid-credit-card"
}

// card/get-report
resource "aws_api_gateway_resource" "card_get_report" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.card.id
  path_part   = "get-report"
}

resource "aws_api_gateway_resource" "card_get_report_id" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.card_get_report.id
  path_part   = "{cardId}"
}

resource "aws_api_gateway_method" "card_get_report_get" {
  rest_api_id   = aws_api_gateway_rest_api.card_api.id
  resource_id   = aws_api_gateway_resource.card_get_report_id.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "card_get_report_get_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.card_api.id
  resource_id             = aws_api_gateway_resource.card_get_report_id.id
  http_method             = aws_api_gateway_method.card_get_report_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.card_get_report_lambda.invoke_arn
}

resource "aws_lambda_permission" "allow_api_gateway_card_get_report" {
  statement_id  = "AllowAPIGatewayInvokeCardGetReport"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.card_get_report_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.card_api.execution_arn}/*/GET/card/get-report/*"
}

# Stage
resource "aws_api_gateway_stage" "card_api_stage" {
  stage_name    = "dev"
  rest_api_id   = aws_api_gateway_rest_api.card_api.id
  deployment_id = aws_api_gateway_deployment.card_api_deployment.id
}

# API Deployment (agrega todos los endpoints aquí en depends_on)
resource "aws_api_gateway_deployment" "card_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.card_create_post_lambda,
    aws_api_gateway_integration.card_activate_post_lambda,
    aws_api_gateway_integration.card_purchase_post_lambda,
    aws_api_gateway_integration.card_transaction_post_lambda,
    aws_api_gateway_integration.card_paid_credit_card_post_lambda,
    aws_api_gateway_integration.card_get_report_get_lambda
  ]
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  description = "Development at ${timestamp()}"
}



# Repite los bloques de API Gateway para los demás endpoints.