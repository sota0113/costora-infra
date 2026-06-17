variable "aws_region" {
  default = "ap-northeast-1"
}

variable "project" {
  default = "costora"
}

variable "vercel_webhook_url" {
  description = "Vercel のWebhookエンドポイント URL（SES請求書転送先）"
  default     = "https://costora.vercel.app/api/webhook/ses-invoice"
}

