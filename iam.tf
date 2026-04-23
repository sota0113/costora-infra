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
