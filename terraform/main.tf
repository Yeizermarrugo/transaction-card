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
    name            = "user_id-index"
    hash_key        = "user_id"
    projection_type = "ALL"
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
    name            = "cardId-index"
    hash_key        = "cardId"
    projection_type = "ALL"
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

resource "aws_s3_bucket" "catalog_bucket" {
  bucket = var.catalog_bucket
  acl    = "private"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids   = [aws_vpc.main.main_route_table_id] # o las RTs específicas de tus subnets
  vpc_endpoint_type = "Gateway"
}
# -----------------------------
# Networking (VPC + subnets)
# -----------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "main-vpc" }
}

resource "aws_subnet" "private_1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_subnet" "private_2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
}


# SQS Queues
resource "aws_sqs_queue" "create_request_card" {
  name   = "create-request-card-sqs"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowRootGetQueueAttributes",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::654654158705:root"
      },
      "Action": "sqs:GetQueueAttributes",
      "Resource": "arn:aws:sqs:us-west-1:654654158705:create-request-card-sqs"
    }
  ]
}
POLICY
}

resource "aws_sqs_queue" "error_create_request_card" {
  name   = "error-create-request-card-sqs"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowRootGetQueueAttributes",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::654654158705:root"
      },
      "Action": "sqs:GetQueueAttributes",
      "Resource": "arn:aws:sqs:us-west-1:654654158705:error-create-request-card-sqs"
    }
  ]
}
POLICY
}


resource "aws_sqs_queue" "start_payment" {
  name = "start-payment-sqs"
}

resource "aws_sqs_queue" "check_balance" {
  name = "check-balance-sqs"
}

resource "aws_sqs_queue" "transaction" {
  name = "transaction-sqs"
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

# Adjuntar policy gestionada AWS para acceso VPC de Lambda
resource "aws_iam_role_policy_attachment" "lambda_vpc_access_managed" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}


resource "aws_elasticache_subnet_group" "main" {
  name       = "redis-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

resource "aws_elasticache_cluster" "main_redis" {
  cluster_id           = "real-time-payment-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  parameter_group_name = "default.redis7"
  security_group_ids   = [aws_security_group.redis_sg.id]
}

# --------- Mapeo de eventos SQS a Lambdas ---------
resource "aws_lambda_event_source_mapping" "start_payment_sqs" {
  event_source_arn = aws_sqs_queue.start_payment.arn
  function_name    = aws_lambda_function.start_payment_lambda.arn
  batch_size       = 1
}

resource "aws_lambda_event_source_mapping" "check_balance_sqs" {
  event_source_arn = aws_sqs_queue.check_balance.arn
  function_name    = aws_lambda_function.check_balance_lambda.arn
  batch_size       = 1
}

resource "aws_lambda_event_source_mapping" "transaction_sqs" {
  event_source_arn = aws_sqs_queue.transaction.arn
  function_name    = aws_lambda_function.transaction_lambda.arn
  batch_size       = 1
}

# ---- Security Group para ElastiCache ----
resource "aws_security_group" "lambda_sg" {
  name        = "lambda-sg"
  vpc_id      = aws_vpc.main.id
  description = "SG para lambdas"
}

resource "aws_security_group" "redis_sg" {
  name        = "redis-sg"
  vpc_id      = aws_vpc.main.id
  description = "SG para Redis"

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_sg.id]
    description     = "Allow Lambda access"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
    SQS_START_PAYMENT_URL  = aws_sqs_queue.start_payment.id
    SQS_CHECK_BALANCE_URL  = aws_sqs_queue.check_balance.id
    SQS_TRANSACTION_URL    = aws_sqs_queue.transaction.id
    REPORT_BUCKET          = aws_s3_bucket.transactions_report.bucket
    CATALOG_BUCKET         = aws_s3_bucket.catalog_bucket.bucket
    REDIS_HOST             = aws_elasticache_cluster.main_redis.cache_nodes.0.address
    REDIS_PORT             = tostring(aws_elasticache_cluster.main_redis.port)
    CORE_API_URL           = var.core_api_url
    CORE_API_KEY           = var.core_api_key
  }
}

# -----------------------------
# Lambda functions (filenames are local zip names - create zips before apply)
# -----------------------------

# create-request-card lambda (placeholder)
resource "aws_lambda_function" "create_request_card_lambda" {
  filename         = "create-request-card-lambda.zip"
  function_name    = "create-request-card-lambda"
  handler          = "create-request-card.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("create-request-card-lambda.zip")
  environment { variables = local.lambda_env_vars }
}

# card-activate (placeholder)
resource "aws_lambda_function" "card_activate_lambda" {
  filename         = "card-activate-lambda.zip"
  function_name    = "card-activate-lambda"
  handler          = "card-activate.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("card-activate-lambda.zip")
  environment { variables = local.lambda_env_vars }
}

# card-purchase (placeholder)
resource "aws_lambda_function" "card_purchase_lambda" {
  filename         = "card-purchase-lambda.zip"
  function_name    = "card-purchase-lambda"
  handler          = "card-purchase.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("card-purchase-lambda.zip")
  environment { variables = local.lambda_env_vars }
}

# card-transaction (placeholder)
resource "aws_lambda_function" "card_transaction_lambda" {
  filename         = "card-transaction-lambda.zip"
  function_name    = "card-transaction-lambda"
  handler          = "card-transaction.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("card-transaction-lambda.zip")
  environment { variables = local.lambda_env_vars }
}

# card-paid-credit-card (placeholder)
resource "aws_lambda_function" "card_paid_credit_card_lambda" {
  filename         = "card-paid-credit-card-lambda.zip"
  function_name    = "card-paid-credit-card-lambda"
  handler          = "card-paid-credit-card.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("card-paid-credit-card-lambda.zip")
  environment { variables = local.lambda_env_vars }
}

# card-get-report (placeholder)
resource "aws_lambda_function" "card_get_report_lambda" {
  filename         = "card-get-report-lambda.zip"
  function_name    = "card-get-report-lambda"
  handler          = "card-get-report.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("card-get-report-lambda.zip")
  environment { variables = local.lambda_env_vars }
}

# get-catalog lambda (reads Redis / S3) - needs VPC for Redis
resource "aws_lambda_function" "get_catalog_lambda" {
  filename         = "get-catalog-lambda.zip"
  function_name    = "get-catalog-lambda"
  handler          = "get-catalog.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("get-catalog-lambda.zip")
  environment { variables = local.lambda_env_vars }
  vpc_config {
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

# post-catalog lambda (uploads to S3 and updates Redis) - needs VPC
resource "aws_lambda_function" "post_catalog_lambda" {
  filename         = "post-catalog-lambda.zip"
  function_name    = "post-catalog-lambda"
  handler          = "post-catalog.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("post-catalog-lambda.zip")
  environment { variables = local.lambda_env_vars }
  vpc_config {
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

# start-payment (API entrypoint that validates card, creates trace and enqueues) - keep OUTSIDE VPC for lower cold-start cost
resource "aws_lambda_function" "start_payment_lambda" {
  filename         = "start-payment-lambda.zip"
  function_name    = "start-payment-lambda"
  handler          = "start-payment.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("start-payment-lambda.zip")
  environment { variables = local.lambda_env_vars }
}

# check-balance consumer (SQS) - needs VPC to access Redis
resource "aws_lambda_function" "check_balance_lambda" {
  filename         = "check-balance-lambda.zip"
  function_name    = "check-balance-lambda"
  handler          = "check-balance.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("check-balance-lambda.zip")
  environment { variables = local.lambda_env_vars }
  vpc_config {
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

# transaction consumer (SQS) - needs VPC if it uses Redis / private core
resource "aws_lambda_function" "transaction_lambda" {
  filename         = "transaction-lambda.zip"
  function_name    = "transaction-lambda"
  handler          = "transaction.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("transaction-lambda.zip")
  environment {
    variables = merge(local.lambda_env_vars, {
      CORE_API_URL = var.core_api_url
      CORE_API_KEY = var.core_api_key
    })
  }
  vpc_config {
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

# get-status (API to poll traceId) - needs VPC to read Redis
resource "aws_lambda_function" "get_status_lambda" {
  filename         = "get-status-lambda.zip"
  function_name    = "get-status-lambda"
  handler          = "get-status.handler"
  runtime          = "nodejs22.x"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("get-status-lambda.zip")
  environment { variables = local.lambda_env_vars }
  vpc_config {
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
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

# ----- GET /card/catalog and POST /card/catalog -----
resource "aws_api_gateway_resource" "catalog" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.card.id
  path_part   = "catalog"
}
resource "aws_api_gateway_method" "get_catalog" {
  rest_api_id   = aws_api_gateway_rest_api.card_api.id
  resource_id   = aws_api_gateway_resource.catalog.id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "get_catalog_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.card_api.id
  resource_id             = aws_api_gateway_resource.catalog.id
  http_method             = aws_api_gateway_method.get_catalog.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_catalog_lambda.invoke_arn
}
resource "aws_lambda_permission" "allow_api_gateway_get_catalog" {
  statement_id  = "AllowAPIGatewayInvokeGetCatalog"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_catalog_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.card_api.execution_arn}/*/GET/card/catalog"
}
resource "aws_api_gateway_method" "post_post_catalog" {
  rest_api_id   = aws_api_gateway_rest_api.card_api.id
  resource_id   = aws_api_gateway_resource.catalog.id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "post_catalog_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.card_api.id
  resource_id             = aws_api_gateway_resource.catalog.id
  http_method             = aws_api_gateway_method.post_post_catalog.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.post_catalog_lambda.invoke_arn
}
resource "aws_lambda_permission" "allow_api_gateway_post_catalog" {
  statement_id  = "AllowAPIGatewayInvokePostCatalog"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_catalog_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.card_api.execution_arn}/*/POST/card/catalog"
}

# ----- GET /card/check-balance/{cardId} -> check-balance lambda (handler supports API proxy) -----
resource "aws_api_gateway_resource" "card_check_balance" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.card.id
  path_part   = "check-balance"
}
resource "aws_api_gateway_resource" "card_check_balance_id" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.card_check_balance.id
  path_part   = "{cardId}"
}
resource "aws_api_gateway_method" "card_check_balance_get" {
  rest_api_id   = aws_api_gateway_rest_api.card_api.id
  resource_id   = aws_api_gateway_resource.card_check_balance_id.id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "check_balance_get_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.card_api.id
  resource_id             = aws_api_gateway_resource.card_check_balance_id.id
  http_method             = aws_api_gateway_method.card_check_balance_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.check_balance_lambda.invoke_arn
}
resource "aws_lambda_permission" "allow_api_gateway_check_balance" {
  statement_id  = "AllowAPIGatewayInvokeCheckBalance"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.check_balance_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.card_api.execution_arn}/*/*/card/check-balance/*"
}

# ----- GET /status/{traceId} -> get-status lambda -----
resource "aws_api_gateway_resource" "status" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.card.id
  path_part   = "status"
}
resource "aws_api_gateway_resource" "status_id" {
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  parent_id   = aws_api_gateway_resource.status.id
  path_part   = "{traceId}"
}
resource "aws_api_gateway_method" "get_status_get" {
  rest_api_id   = aws_api_gateway_rest_api.card_api.id
  resource_id   = aws_api_gateway_resource.status_id.id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "get_status_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.card_api.id
  resource_id             = aws_api_gateway_resource.status_id.id
  http_method             = aws_api_gateway_method.get_status_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_status_lambda.invoke_arn
}
resource "aws_lambda_permission" "allow_api_gateway_get_status" {
  statement_id  = "AllowAPIGatewayInvokeGetStatus"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_status_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.card_api.execution_arn}/*/GET/card/status/*"
}


# ----- /card/transaction/{cardId} -> start-payment -----
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
  uri                     = aws_lambda_function.start_payment_lambda.invoke_arn
}
resource "aws_lambda_permission" "allow_api_gateway_start_payment" {
  statement_id  = "AllowAPIGatewayInvokeStartPayment"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_payment_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.card_api.execution_arn}/*/POST/card/transaction/*"
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
    aws_api_gateway_integration.card_get_report_get_lambda,
    aws_api_gateway_integration.check_balance_get_lambda,
    aws_api_gateway_integration.get_catalog_lambda,
    aws_api_gateway_integration.post_catalog_lambda
  ]
  rest_api_id = aws_api_gateway_rest_api.card_api.id
  description = "Development at ${timestamp()}"
}



# Repite los bloques de API Gateway para los demás endpoints.
