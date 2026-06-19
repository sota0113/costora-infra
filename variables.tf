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

variable "inference_domain" {
  description = "推論サーバーのドメイン名（costora.net DNS解決後は inference.costora.net に戻す）"
  default     = "inference.patrae.net"
}

