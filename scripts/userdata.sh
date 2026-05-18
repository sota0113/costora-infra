#!/bin/bash
set -e

# ── Ollama ───────────────────────────────────────────────────────────
export HOME=/root
curl -fsSL https://ollama.com/install.sh | sh
systemctl enable ollama
systemctl start ollama
sleep 15
ollama pull llama3.1:8b

# ── Python deps ──────────────────────────────────────────────────────
dnf install -y python3-pip nginx
pip3 install \
  fastapi \
  "uvicorn[standard]" \
  pymupdf \
  requests \
  jsonschema \
  python-multipart \
  openpyxl \
  mammoth \
  certbot \
  certbot-dns-route53

# ── FastAPI app ──────────────────────────────────────────────────────
mkdir -p /opt/inference
base64 -d > /opt/inference/main.py << 'B64EOF'
${inference_api_b64}
B64EOF

cat > /etc/systemd/system/inference.service << 'UNIT'
[Unit]
Description=Inference FastAPI Server
After=network.target ollama.service

[Service]
ExecStart=/usr/local/bin/uvicorn main:app --host 127.0.0.1 --port 8000
WorkingDirectory=/opt/inference
Restart=always
Environment=OLLAMA_HOST=http://localhost:11434

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable inference
systemctl start inference

# ── nginx (HTTP only with API key auth) ──────────────────────────────
cat > /etc/nginx/conf.d/inference.conf << 'NGINXEOF'
server {
    listen 80;
    server_name inference.costora.net;
    client_max_body_size 50M;

    if ($$http_x_api_key != "${inference_api_key}") {
        return 401;
    }

    location / {
        proxy_pass         http://127.0.0.1:8000;
        proxy_set_header   Host $$host;
        proxy_set_header   X-Real-IP $$remote_addr;
        proxy_read_timeout 600s;
    }
}
NGINXEOF

systemctl enable nginx
systemctl start nginx

# ── TLS setup script ─────────────────────────────────────────────────
base64 -d > /opt/setup-tls.sh << 'B64EOF'
${setup_tls_b64}
B64EOF
chmod +x /opt/setup-tls.sh

# Try TLS now (succeeds only if Route53 NS is already propagated)
/opt/setup-tls.sh || echo "[warn] TLS skipped. Run /opt/setup-tls.sh via SSM after DNS propagates."
