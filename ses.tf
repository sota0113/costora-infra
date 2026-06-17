# ── SES Domain Identity (us-east-1) ──────────────────────────────────────────

resource "aws_ses_domain_identity" "costora" {
  provider = aws.us_east_1
  domain   = "costora.net"
}

resource "aws_route53_record" "ses_verification" {
  zone_id = aws_route53_zone.costora.zone_id
  name    = "_amazonses.costora.net"
  type    = "TXT"
  ttl     = 300
  records = [aws_ses_domain_identity.costora.verification_token]
}

resource "aws_ses_domain_identity_verification" "costora" {
  provider   = aws.us_east_1
  domain     = aws_ses_domain_identity.costora.id
  depends_on = [aws_route53_record.ses_verification]
}

resource "aws_ses_domain_dkim" "costora" {
  provider = aws.us_east_1
  domain   = aws_ses_domain_identity.costora.domain
}

resource "aws_route53_record" "ses_dkim" {
  count   = 3
  zone_id = aws_route53_zone.costora.zone_id
  name    = "${aws_ses_domain_dkim.costora.dkim_tokens[count.index]}._domainkey.costora.net"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.costora.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# ── MX Record for inbound email ───────────────────────────────────────────────

resource "aws_route53_record" "ses_mx" {
  zone_id = aws_route53_zone.costora.zone_id
  name    = "mail.costora.net"
  type    = "MX"
  ttl     = 300
  records = ["10 inbound-smtp.us-east-1.amazonaws.com"]
}

# ── S3 Bucket for received emails (us-east-1) ─────────────────────────────────

resource "aws_s3_bucket" "ses_emails" {
  provider = aws.us_east_1
  bucket   = "costora-ses-emails-${data.aws_caller_identity.current.account_id}"
  tags     = { Project = var.project }
}

resource "aws_s3_bucket_lifecycle_configuration" "ses_emails" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.ses_emails.id

  rule {
    id     = "expire-emails"
    status = "Enabled"

    filter { prefix = "incoming/" }

    expiration { days = 7 }
  }
}

# SESがS3にPutObjectできるポリシー
resource "aws_s3_bucket_policy" "ses_emails" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.ses_emails.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSESPuts"
      Effect    = "Allow"
      Principal = { Service = "ses.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.ses_emails.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

# ── SES Receipt Rule Set ──────────────────────────────────────────────────────

resource "aws_ses_receipt_rule_set" "main" {
  provider      = aws.us_east_1
  rule_set_name = "costora-main"
}

resource "aws_ses_active_receipt_rule_set" "main" {
  provider      = aws.us_east_1
  rule_set_name = aws_ses_receipt_rule_set.main.rule_set_name
}

resource "aws_ses_receipt_rule" "invoice" {
  provider      = aws.us_east_1
  name          = "invoice-to-s3"
  rule_set_name = aws_ses_receipt_rule_set.main.rule_set_name
  recipients    = ["mail.costora.net"]
  enabled       = true
  scan_enabled  = true

  s3_action {
    bucket_name       = aws_s3_bucket.ses_emails.id
    object_key_prefix = "incoming/"
    position          = 1
  }

  depends_on = [
    aws_s3_bucket_policy.ses_emails,
    aws_ses_domain_identity_verification.costora,
  ]
}

# ── Lambda IAM ────────────────────────────────────────────────────────────────

resource "aws_iam_role" "ses_lambda" {
  provider = aws.us_east_1
  name     = "costora-ses-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Project = var.project }
}

resource "aws_iam_role_policy" "ses_lambda" {
  provider = aws.us_east_1
  name     = "costora-ses-lambda-policy"
  role     = aws_iam_role.ses_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.ses_emails.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:us-east-1:*:*"
      }
    ]
  })
}

# ── Lambda Function ───────────────────────────────────────────────────────────

data "archive_file" "ses_handler" {
  type        = "zip"
  source_file = "${path.module}/scripts/ses_invoice_handler.py"
  output_path = "${path.module}/.terraform/ses_invoice_handler.zip"
}

resource "aws_lambda_function" "ses_invoice" {
  provider         = aws.us_east_1
  function_name    = "costora-ses-invoice-handler"
  role             = aws_iam_role.ses_lambda.arn
  handler          = "ses_invoice_handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.ses_handler.output_path
  source_code_hash = data.archive_file.ses_handler.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      WEBHOOK_URL    = var.vercel_webhook_url
      WEBHOOK_SECRET = random_password.ses_webhook_secret.result
    }
  }

  tags = { Project = var.project }
}

resource "aws_lambda_permission" "s3_invoke_ses" {
  provider      = aws.us_east_1
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ses_invoice.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.ses_emails.arn
}

resource "aws_s3_bucket_notification" "ses_emails" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.ses_emails.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ses_invoice.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "incoming/"
  }

  depends_on = [aws_lambda_permission.s3_invoke_ses]
}
