data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_iam_role" "ollama" {
  name = "${var.project}-ollama"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = var.project
  }
}

resource "aws_iam_role_policy_attachment" "ollama_ssm" {
  role       = aws_iam_role.ollama.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ollama_route53" {
  name = "${var.project}-ollama-route53"
  role = aws_iam_role.ollama.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "route53:GetChange",
        "route53:ChangeResourceRecordSets",
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "ollama_bedrock" {
  name = "${var.project}-ollama-bedrock"
  role = aws_iam_role.ollama.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["bedrock:InvokeModel"]
      Resource = [
        "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
        "arn:aws:bedrock:us-east-1:*:inference-profile/us.anthropic.claude-haiku-4-5-20251001-v1:0",
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "ollama" {
  name = "${var.project}-ollama"
  role = aws_iam_role.ollama.name
}

resource "aws_security_group" "ollama" {
  name        = "${var.project}-ollama"
  description = "Inference server"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

resource "aws_instance" "ollama" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.medium"
  iam_instance_profile   = aws_iam_instance_profile.ollama.name
  vpc_security_group_ids = [aws_security_group.ollama.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/scripts/userdata.sh", {
    inference_api_b64 = base64encode(file("${path.module}/scripts/inference_api.py"))
    setup_tls_b64 = base64encode(templatefile("${path.module}/scripts/setup_tls.sh", {
      inference_api_key = random_password.inference_api_key.result
    }))
    inference_api_key = random_password.inference_api_key.result
  })

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
  instance_id   = aws_instance.ollama.id
  allocation_id = aws_eip.ollama.id
}
