variable "aws_region" {
  default = "ap-northeast-1"
}

variable "project" {
  default = "costora"
}

variable "ollama_allowed_cidrs" {
  description = "CIDRs allowed to access Ollama API and SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ollama_key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
  default     = ""
}
