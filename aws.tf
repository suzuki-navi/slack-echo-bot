variable aws_profile {}
variable aws_region {}
variable resource_name {}
variable slack_signing_secret {}
variable slack_bot_token {}

terraform {
  backend "s3" {
  }
}

provider "aws" {
   profile = var.aws_profile
   region = var.aws_region
}

################################################################################
# ECR
################################################################################

resource "aws_ecr_repository" "default" {
  name = var.resource_name
  force_delete = true
}

################################################################################
# docker push
################################################################################

locals {
  docker_source_file_sha1 = sha1(join("", [for f in ["build-docker.sh", "Dockerfile", "app.js", "package.json"]: filesha1(f)]))
}

resource "null_resource" "image" {
  depends_on = [
    aws_ecr_repository.default
  ]

  triggers = {
    file_content_sha1 = local.docker_source_file_sha1
  }

  provisioner "local-exec" {
    command = "sh ./build-docker.sh"
  }
}

################################################################################
# Lambda
################################################################################

resource "aws_iam_role" "lambda_role" {
  name               = "${var.resource_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_lambda_function" "api" {
  depends_on       = [
    aws_iam_role.lambda_role,
    null_resource.image,
  ]
  function_name    = "${var.resource_name}-api"
  role             = aws_iam_role.lambda_role.arn
  package_type     = "Image"
  image_uri        = "${aws_ecr_repository.default.repository_url}:latest"
  timeout          = 30
  environment {
    variables = {
      "SLACK_SIGNING_SECRET" = var.slack_signing_secret
      "SLACK_BOT_TOKEN" = var.slack_bot_token
    }
  }
}

resource "null_resource" "refresh_lambda" {
  depends_on = [
    aws_lambda_function.api,
    null_resource.image,
  ]

  triggers = {
    // イメージを更新したときに新しいイメージでLambdaを更新するためのトリガー
    file_content_sha1 = local.docker_source_file_sha1
  }

  provisioner "local-exec" {
    command = "sh ./refresh-lambda.sh"
  }
}

################################################################################
# API Gateway
################################################################################

resource "aws_iam_role" "api_gateway_role" {
  name               = "${var.resource_name}-apigateway-role"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role.json
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_logs" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_lambda" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaRole"
}

data "aws_iam_policy_document" "api_gateway_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name = "${var.resource_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  body = jsonencode({
    openapi = "3.0.1"
    info = {
      title   = "api"
      version = "1.0"
    }
    paths = {
      "/slack/events" = {
        post = {
          x-amazon-apigateway-integration = {
            httpMethod           = "POST"
            payloadFormatVersion = "1.0"
            type                 = "AWS_PROXY"
            uri                  = aws_lambda_function.api.invoke_arn
            credentials          = aws_iam_role.api_gateway_role.arn
          }
        }
      }
    }
  })
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  depends_on  = [aws_api_gateway_rest_api.api]
  stage_name  = "prod"
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api))
  }
}

output "invoke_url" {
  value = "${aws_api_gateway_deployment.deployment.invoke_url}/slack/events"
}

################################################################################
