resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = {
    Project = var.project
  }
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:sota0113/costora-infra:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Project = var.project
  }
}

resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "${var.project}-github-actions-terraform"
  role = aws_iam_role.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:TagResource",
          "dynamodb:UntagResource",
          "dynamodb:ListTagsOfResource",
        ]
        Resource = "arn:aws:dynamodb:*:*:table/${var.project}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateUser",
          "iam:DeleteUser",
          "iam:GetUser",
          "iam:TagUser",
          "iam:UntagUser",
          "iam:PutUserPolicy",
          "iam:DeleteUserPolicy",
          "iam:GetUserPolicy",
          "iam:CreateAccessKey",
          "iam:DeleteAccessKey",
          "iam:ListAccessKeys",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:PassRole",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_user" "app" {
  name = "${var.project}-app"

  tags = {
    Project = var.project
  }
}

resource "aws_iam_user_policy" "dynamodb" {
  name = "${var.project}-dynamodb-access"
  user = aws_iam_user.app.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
      ]
      Resource = aws_dynamodb_table.keys.arn
    }]
  })
}

resource "aws_iam_access_key" "app" {
  user = aws_iam_user.app.name
}

resource "aws_iam_user" "invoice" {
  name = "${var.project}-invoice"

  tags = {
    Project = var.project
  }
}

resource "aws_iam_user_policy" "invoice" {
  name = "${var.project}-invoice-access"
  user = aws_iam_user.invoice.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "textract:StartDocumentAnalysis",
          "textract:GetDocumentAnalysis",
          "textract:DetectDocumentText",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "arn:aws:s3:::${var.project}-invoice/*"
      },
    ]
  })
}

resource "aws_iam_access_key" "invoice" {
  user = aws_iam_user.invoice.name
}
