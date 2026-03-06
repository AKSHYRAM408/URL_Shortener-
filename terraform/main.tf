# ──────────────────────────────────────────────────────────────────
# URL Shortener — Terraform Configuration
# Creates: DynamoDB table, Lambda function, IAM role, API Gateway
# Region: ap-south-1 (Mumbai) — 100 % Free Tier
# ──────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── Account Data (for billing alarm) ────────────────────────────
data "aws_caller_identity" "current" {}

# ─── Local Values ────────────────────────────────────────────────
locals {
  project    = "url-shortener"
  table_name = "url-shortener"
}

# ──────────────────────────────────────────────────────────────────
# 1. DynamoDB Table
# ──────────────────────────────────────────────────────────────────
resource "aws_dynamodb_table" "urls" {
  name         = local.table_name
  billing_mode = "PROVISIONED" # provisioned = guaranteed always-free (25 RCU/WCU)
  hash_key     = "short_code"

  read_capacity  = 1 # Free Tier allows up to 25
  write_capacity = 1 # Free Tier allows up to 25

  attribute {
    name = "short_code"
    type = "S"
  }

  tags = {
    Project = local.project
  }
}

# ──────────────────────────────────────────────────────────────────
# 2. IAM Role for Lambda
# ──────────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${local.project}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags = {
    Project = local.project
  }
}

# Attach basic Lambda execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# DynamoDB permissions for the Lambda
data "aws_iam_policy_document" "dynamodb_access" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:Scan",
    ]
    resources = [aws_dynamodb_table.urls.arn]
  }
}

resource "aws_iam_policy" "dynamodb_access" {
  name   = "${local.project}-dynamodb-access"
  policy = data.aws_iam_policy_document.dynamodb_access.json
}

resource "aws_iam_role_policy_attachment" "dynamodb" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.dynamodb_access.arn
}

# ──────────────────────────────────────────────────────────────────
# 3. Lambda Function
# ──────────────────────────────────────────────────────────────────
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../app/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "url_shortener" {
  function_name    = local.project
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.urls.name
    }
  }

  tags = {
    Project = local.project
  }
}

# ──────────────────────────────────────────────────────────────────
# 4. API Gateway (REST API)
# ──────────────────────────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "api" {
  name        = "${local.project}-api"
  description = "Public REST API for the URL Shortener"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Project = local.project
  }
}

# ── POST /shorten ────────────────────────────────────────────────
resource "aws_api_gateway_resource" "shorten" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "shorten"
}

resource "aws_api_gateway_method" "shorten_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.shorten.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "shorten_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.shorten.id
  http_method             = aws_api_gateway_method.shorten_post.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.url_shortener.invoke_arn
}

# ── OPTIONS /shorten (CORS) ─────────────────────────────────────
resource "aws_api_gateway_method" "shorten_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.shorten.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "shorten_options" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.shorten.id
  http_method             = aws_api_gateway_method.shorten_options.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.url_shortener.invoke_arn
}

# ── GET /{code} (redirect) ──────────────────────────────────────
resource "aws_api_gateway_resource" "redirect" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{code}"
}

resource "aws_api_gateway_method" "redirect_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.redirect.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.code" = true
  }
}

resource "aws_api_gateway_integration" "redirect_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.redirect.id
  http_method             = aws_api_gateway_method.redirect_get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.url_shortener.invoke_arn
}

# ── GET /stats/{code} ───────────────────────────────────────────
resource "aws_api_gateway_resource" "stats" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "stats"
}

resource "aws_api_gateway_resource" "stats_code" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.stats.id
  path_part   = "{code}"
}

resource "aws_api_gateway_method" "stats_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.stats_code.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.code" = true
  }
}

resource "aws_api_gateway_integration" "stats_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.stats_code.id
  http_method             = aws_api_gateway_method.stats_get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.url_shortener.invoke_arn
}

# ── Deploy the API ───────────────────────────────────────────────
resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_integration.shorten_post,
    aws_api_gateway_integration.shorten_options,
    aws_api_gateway_integration.redirect_get,
    aws_api_gateway_integration.stats_get,
  ]

  # Force new deployment on any change
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.shorten,
      aws_api_gateway_method.shorten_post,
      aws_api_gateway_integration.shorten_post,
      aws_api_gateway_resource.redirect,
      aws_api_gateway_method.redirect_get,
      aws_api_gateway_integration.redirect_get,
      aws_api_gateway_resource.stats_code,
      aws_api_gateway_method.stats_get,
      aws_api_gateway_integration.stats_get,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deploy.id
  stage_name    = var.api_stage_name

  tags = {
    Project = local.project
  }
}

# ── Lambda Permission for API Gateway ────────────────────────────
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.url_shortener.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# ──────────────────────────────────────────────────────────────────
# 5. Billing Safety Net — $1 Budget Alarm
# ──────────────────────────────────────────────────────────────────
resource "aws_budgets_budget" "zero_cost_guard" {
  name         = "${local.project}-zero-cost-guard"
  budget_type  = "COST"
  limit_amount = "1.0"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80 # alert at $0.80 (80% of $1)
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100 # alert when you hit $1
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
