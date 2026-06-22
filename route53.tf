resource "aws_route53_zone" "costora" {
  name = "costora.net"

  tags = {
    Project = var.project
  }
}

resource "aws_route53_record" "inference" {
  zone_id = aws_route53_zone.costora.zone_id
  name    = "inference.costora.net"
  type    = "A"
  ttl     = 300
  records = [aws_eip.ollama.public_ip]
}
