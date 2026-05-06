resource "aws_s3_bucket" "invoice" {
  bucket = "${var.project}-invoice"

  tags = {
    Project = var.project
  }
}

resource "aws_s3_bucket_public_access_block" "invoice" {
  bucket = aws_s3_bucket.invoice.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "invoice" {
  bucket = aws_s3_bucket.invoice.id

  rule {
    id     = "expire-after-14-days"
    status = "Enabled"

    expiration {
      days = 14
    }
  }
}
