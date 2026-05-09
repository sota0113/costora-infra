output "dynamodb_table_name" {
  value = aws_dynamodb_table.keys.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.keys.arn
}

output "iam_user_name" {
  value = aws_iam_user.app.name
}

output "access_key_id" {
  value = aws_iam_access_key.app.id
}

output "secret_access_key" {
  value     = aws_iam_access_key.app.secret
  sensitive = true
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "invoice_s3_bucket" {
  value = aws_s3_bucket.invoice.bucket
}

output "ollama_endpoint" {
  value = "http://${aws_eip.ollama.public_ip}:11434"
}
