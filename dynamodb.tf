resource "aws_dynamodb_table" "keys" {
  name         = "${var.project}-keys"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "tenantKey"
  range_key    = "service"

  attribute {
    name = "tenantKey"
    type = "S"
  }

  attribute {
    name = "service"
    type = "S"
  }

  tags = {
    Project = var.project
  }
}
