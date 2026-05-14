resource "aws_route53_zone" "patrae" {
  name = "patrae.net"

  tags = {
    Project = var.project
  }
}

resource "aws_route53_record" "inference" {
  zone_id = aws_route53_zone.patrae.zone_id
  name    = "inference.patrae.net"
  type    = "A"
  ttl     = 300
  records = [aws_eip.ollama.public_ip]
}
