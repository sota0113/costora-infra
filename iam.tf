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
          "dynamodb:UpdateTable",
          "dynamodb:TagResource",
          "dynamodb:UntagResource",
          "dynamodb:Describe*",
          "dynamodb:List*",
        ]
        Resource = "arn:aws:dynamodb:*:*:table/${var.project}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = [
          "arn:aws:s3:::costora-tfstate-143985718717-ap-northeast-1-an/*",
          "arn:aws:s3:::${var.project}-invoice/*",
        ]
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::costora-tfstate-143985718717-ap-northeast-1-an",
          "arn:aws:s3:::${var.project}-invoice",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:GetBucketVersioning",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetBucketRequestPayment",
          "s3:GetBucketWebsite",
          "s3:GetBucketLogging",
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketCORS",
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:GetEncryptionConfiguration",
        ]
        Resource = "arn:aws:s3:::${var.project}-invoice"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:Create*",
          "iam:Delete*",
          "iam:Get*",
          "iam:List*",
          "iam:Put*",
          "iam:Tag*",
          "iam:Untag*",
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
