data "aws_ami" "deep_learning" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning OSS Nvidia Driver AMI GPU * (Amazon Linux 2023) *"]
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

resource "aws_iam_instance_profile" "ollama" {
  name = "${var.project}-ollama"
  role = aws_iam_role.ollama.name
}

resource "aws_security_group" "ollama" {
  name        = "${var.project}-ollama"
  description = "Ollama inference server"

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

  ingress {
    description = "Ollama API"
    from_port   = 11434
    to_port     = 11434
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
  iam_instance_profile           = aws_iam_instance_profile.ollama.name
  vpc_security_group_ids         = [aws_security_group.ollama.id]

  root_block_device {
    volume_size = 50
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
  instance_id   = aws_spot_instance_request.ollama.spot_instance_id
  allocation_id = aws_eip.ollama.id
}
