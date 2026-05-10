variable "aws_region" {
  default = "ap-northeast-1"
}

variable "project" {
  default = "costora"
}

variable "ollama_allowed_cidrs" {
  description = "CIDRs allowed to access Ollama API"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "inference_api_key" {
  description = "Secret key for nginx API authentication (X-Api-Key header)"
  type        = string
  sensitive   = true
}
