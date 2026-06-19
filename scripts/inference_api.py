from __future__ import annotations

import base64
import io
import json
import os
from typing import Any, Optional

import boto3
import fitz  # PyMuPDF
import jsonschema
from fastapi import FastAPI, File, HTTPException, UploadFile
from pydantic import BaseModel

app = FastAPI()

MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "us.anthropic.claude-haiku-4-5-20251001-v1:0")
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "us-east-1")
MAX_CHARS = 12_000

IMAGE_MEDIA_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
}

_bedrock = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)


class ParsedField(BaseModel):
    productName: str
    subtotal: Optional[float] = None
    expiryDate: Optional[str] = None
    currency: Optional[str] = None
    billingPeriodStart: Optional[str] = None
    billingPeriodEnd: Optional[str] = None


class ParseResponse(BaseModel):
    fields: list[ParsedField]


INVOICE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "fields": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "productName": {"type": "string"},
                    "subtotal": {"type": ["number", "null"]},
                    "expiryDate": {"type": ["string", "null"]},
                    "currency": {"type": ["string", "null"]},
                    "billingPeriodStart": {"type": ["string", "null"]},
                    "billingPeriodEnd": {"type": ["string", "null"]},
                },
                "required": ["productName", "subtotal", "expiryDate", "currency", "billingPeriodStart", "billingPeriodEnd"],
            },
        }
    },
    "required": ["fields"],
}

_EXTRACTION_INSTRUCTIONS = """# 抽出するフィールド
- productName: 商品・サービス名
- subtotal: 小計金額（税抜き金額。税込合計ではなく小計を抽出）
- expiryDate: 契約・ライセンスの有効期限（YYYY-MM-DD形式、なければnull）
- currency: 通貨コード（JPY, USD, EURなど。請求書の通貨記号から判断）
- billingPeriodStart: 請求期間の開始日（YYYY-MM-DD形式、なければnull）
- billingPeriodEnd: 請求期間の終了日（YYYY-MM-DD形式、なければnull）

# ルール
- 出力は **JSON のみ**。説明文・前置き・コードブロック記号は禁止。
- 値が文書中に存在しない場合は null を入れる。推測しない。
- 数値は数値型で、日付は ISO 8601 (YYYY-MM-DD) で返す。
- 文書の言語に関わらず、フィールド名はスキーマ通り英語のまま。"""


def build_prompt(text: str) -> str:
    schema_str = json.dumps(INVOICE_SCHEMA, ensure_ascii=False, indent=2)
    return f"""あなたは厳密な情報抽出アシスタントです。
以下のドキュメントから、指定された JSON Schema に従って情報を抽出してください。

{_EXTRACTION_INSTRUCTIONS}

# JSON Schema
{schema_str}

# ドキュメント
{text}

# 出力 (JSON のみ)
"""


def build_image_content(
    image_bytes: bytes,
    media_type: str,
    last_error: str | None = None,
    last_raw: str | None = None,
) -> list[dict[str, Any]]:
    schema_str = json.dumps(INVOICE_SCHEMA, ensure_ascii=False, indent=2)
    text = f"""この画像は請求書です。画像から指定された JSON Schema に従って情報を抽出してください。

{_EXTRACTION_INSTRUCTIONS}

# JSON Schema
{schema_str}

# 出力 (JSON のみ)
"""
    if last_error and last_raw:
        text += (
            f"\n\n# 前回の出力 (壊れていた)\n{last_raw}\n"
            f"# エラー\n{last_error}\n"
            "上記を修正して、有効な JSON のみを返してください。\n"
        )
    return [
        {
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": media_type,
                "data": base64.b64encode(image_bytes).decode("utf-8"),
            },
        },
        {"type": "text", "text": text},
    ]


def call_bedrock(content: Any) -> dict[str, Any]:
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 4096,
        "temperature": 0.0,
        "messages": [{"role": "user", "content": content}],
    }
    try:
        response = _bedrock.invoke_model(
            modelId=MODEL_ID,
            contentType="application/json",
            accept="application/json",
            body=json.dumps(body),
        )
    except Exception as e:
        raise RuntimeError(f"Bedrock API error: {e}") from e

    result = json.loads(response["body"].read())
    raw = result["content"][0]["text"].strip()
    # Claude がコードフェンスで囲んだ場合に備えて除去
    if raw.startswith("```"):
        parts = raw.split("```")
        raw = parts[1].lstrip("json").strip()
    return json.loads(raw)


def extract_with_validation(
    text: str | None = None,
    image_bytes: bytes | None = None,
    image_media_type: str | None = None,
) -> dict[str, Any]:
    last_error: str | None = None
    last_raw: str | None = None

    for _ in range(2):
        if image_bytes is not None:
            content: Any = build_image_content(image_bytes, image_media_type, last_error, last_raw)
        else:
            assert text is not None
            content = build_prompt(text)
            if last_error and last_raw:
                content += (
                    f"\n\n# 前回の出力 (壊れていた)\n{last_raw}\n"
                    f"# エラー\n{last_error}\n"
                    "上記を修正して、有効な JSON のみを返してください。\n"
                )

        result = call_bedrock(content)
        last_raw = json.dumps(result)

        try:
            jsonschema.validate(instance=result, schema=INVOICE_SCHEMA)
            return result
        except jsonschema.ValidationError as e:
            path = "/".join(map(str, e.path)) or "<root>"
            last_error = f"{path}: {e.message}"

    raise ValueError(
        f"スキーマに合う JSON を生成できませんでした。最後のエラー: {last_error}"
    )


@app.post("/parse", response_model=ParseResponse)
async def parse_invoice(file: UploadFile = File(...)) -> ParseResponse:
    content = await file.read()
    filename = (file.filename or "").lower()

    try:
        ext = next((e for e in IMAGE_MEDIA_TYPES if filename.endswith(e)), None)
        if ext is not None:
            raw = extract_with_validation(image_bytes=content, image_media_type=IMAGE_MEDIA_TYPES[ext])
        elif filename.endswith(".pdf"):
            doc = fitz.open(stream=content, filetype="pdf")
            text = "\n".join(
                f"--- Page {i + 1} ---\n{page.get_text('text')}"
                for i, page in enumerate(doc)
            )
            if len(text) > MAX_CHARS:
                text = text[:MAX_CHARS]
            raw = extract_with_validation(text=text)
        elif filename.endswith((".xlsx", ".xls")):
            import openpyxl
            wb = openpyxl.load_workbook(io.BytesIO(content), data_only=True)
            rows = [
                ",".join(str(c) if c is not None else "" for c in row)
                for ws in wb.worksheets
                for row in ws.iter_rows(values_only=True)
            ]
            text = "\n".join(rows)
            if len(text) > MAX_CHARS:
                text = text[:MAX_CHARS]
            raw = extract_with_validation(text=text)
        elif filename.endswith((".docx", ".doc")):
            import mammoth
            result = mammoth.extract_raw_text(io.BytesIO(content))
            text = result.value
            if len(text) > MAX_CHARS:
                text = text[:MAX_CHARS]
            raw = extract_with_validation(text=text)
        else:
            text = content.decode("utf-8", errors="replace")
            if len(text) > MAX_CHARS:
                text = text[:MAX_CHARS]
            raw = extract_with_validation(text=text)

        return ParseResponse(fields=[ParsedField(**f) for f in raw.get("fields", [])])

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
