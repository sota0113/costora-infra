"""
Lambda handler: SES受信メール → 添付ファイル → Vercel webhook

フロー:
  S3 event → メールをS3からダウンロード → To ヘッダーからitemIdを抽出
  → 添付ファイル(PDF/Excel/Word)をbase64エンコード
  → POST /api/webhook/ses-invoice (Vercel)
"""
from __future__ import annotations

import base64
import email
import json
import os
import urllib.parse
import urllib.request


SUPPORTED_EXTENSIONS = frozenset(("pdf", "xlsx", "xls", "docx", "doc"))


def handler(event, context):
    import boto3

    s3 = boto3.client("s3")

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        obj = s3.get_object(Bucket=bucket, Key=key)
        raw_email = obj["Body"].read()

        msg = email.message_from_bytes(raw_email)

        # invoice-{itemId}@mail.costora.net
        to_addr = (msg.get("To") or msg.get("Delivered-To") or "").strip()
        local_part = to_addr.split("@")[0].strip("<> ")
        if not local_part.startswith("invoice-"):
            print(f"Skip: not an invoice address ({to_addr})")
            continue

        item_id = local_part[len("invoice-"):]
        print(f"Processing invoice for itemId={item_id}")

        for part in msg.walk():
            if "attachment" not in (part.get("Content-Disposition") or ""):
                continue

            filename = part.get_filename()
            if not filename:
                continue

            ext = filename.lower().rsplit(".", 1)[-1] if "." in filename else ""
            if ext not in SUPPORTED_EXTENSIONS:
                print(f"Skip unsupported attachment: {filename}")
                continue

            payload = part.get_payload(decode=True)
            if not payload:
                continue

            _call_webhook(item_id, filename, base64.b64encode(payload).decode("utf-8"))


def _call_webhook(item_id: str, filename: str, file_b64: str) -> None:
    webhook_url = os.environ["WEBHOOK_URL"]
    webhook_secret = os.environ["WEBHOOK_SECRET"]

    body = json.dumps(
        {"itemId": item_id, "filename": filename, "fileBase64": file_b64}
    ).encode("utf-8")

    req = urllib.request.Request(
        webhook_url,
        data=body,
        headers={
            "Content-Type": "application/json",
            "X-Webhook-Secret": webhook_secret,
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            result = json.loads(resp.read())
            print(f"Webhook OK: {result}")
    except urllib.error.HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")
        print(f"Webhook HTTP error {e.code}: {body_text}")
    except Exception as e:
        print(f"Webhook error: {e}")
