data "aws_ami" "deep_learning" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning OSS Nvidia Driver AMI (Amazon Linux 2023)*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_security_group" "ollama" {
  name        = "${var.project}-ollama"
  description = "Ollama inference server"

  ingress {
    description = "Ollama API"
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = var.ollama_allowed_cidrs
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ollama_allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project
  }
}

resource "aws_spot_instance_request" "ollama" {
  ami                            = data.aws_ami.deep_learning.id
  instance_type                  = "g4dn.xlarge"
  spot_type                      = "persistent"
  instance_interruption_behavior = "stop"
  wait_for_fulfillment           = true
  key_name                       = var.ollama_key_name
  vpc_security_group_ids         = [aws_security_group.ollama.id]

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    curl -fsSL https://ollama.com/install.sh | sh
    systemctl enable ollama
    systemctl start ollama
    sleep 15
    ollama pull llama3.1:8b
  EOF

  tags = {
    Project = var.project
    Name    = "${var.project}-ollama"
  }
}

resource "aws_eip" "ollama" {
  domain = "vpc"

  tags = {
    Project = var.project
  }
}

resource "aws_eip_association" "ollama" {
  instance_id   = aws_spot_instance_request.ollama.spot_instance_id
  allocation_id = aws_eip.ollama.id
}
