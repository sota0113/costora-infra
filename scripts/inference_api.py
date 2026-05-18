from __future__ import annotations

import io
import json
import os
from typing import Any

import fitz  # PyMuPDF
import requests
from fastapi import FastAPI, File, HTTPException, UploadFile
import jsonschema

app = FastAPI()

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
MODEL = os.environ.get("OLLAMA_MODEL", "llama3.1:8b")
MAX_CHARS = 12_000

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
                },
                "required": ["productName", "subtotal", "expiryDate"],
            },
        }
    },
    "required": ["fields"],
}


def build_prompt(text: str) -> str:
    schema_str = json.dumps(INVOICE_SCHEMA, ensure_ascii=False, indent=2)
    return f"""あなたは厳密な情報抽出アシスタントです。
以下のドキュメントから、指定された JSON Schema に従って情報を抽出してください。

# ルール
- 出力は **JSON のみ**。説明文・前置き・コードブロック記号は禁止。
- 値が文書中に存在しない場合は null を入れる。推測しない。
- 数値は数値型で、日付は ISO 8601 (YYYY-MM-DD) で返す。
- 文書の言語に関わらず、フィールド名はスキーマ通り英語のまま。

# JSON Schema
{schema_str}

# ドキュメント
{text}

# 出力 (JSON のみ)
"""


def call_ollama(prompt: str) -> dict[str, Any]:
    payload = {
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "options": {"temperature": 0.0, "num_ctx": 8192},
    }
    try:
        resp = requests.post(
            f"{OLLAMA_HOST}/api/generate", json=payload, timeout=600
        )
        resp.raise_for_status()
    except requests.RequestException as e:
        raise RuntimeError(f"Ollama API error: {e}") from e

    raw = resp.json().get("response", "").strip()
    return json.loads(raw)


def extract_with_validation(text: str) -> dict[str, Any]:
    last_error: str | None = None
    last_raw: str | None = None

    for _ in range(2):
        prompt = build_prompt(text)
        if last_error and last_raw:
            prompt += (
                f"\n\n# 前回の出力 (壊れていた)\n{last_raw}\n"
                f"# エラー\n{last_error}\n"
                "上記を修正して、有効な JSON のみを返してください。\n"
            )

        result = call_ollama(prompt)
        last_raw = json.dumps(result)

        try:
            jsonschema.validate(instance=result, schema=INVOICE_SCHEMA)
            return result
        except jsonschema.ValidationError as e:
            last_error = f"{'/'.join(map(str, e.path)) or '<root>'}: {e.message}"

    raise ValueError(
        f"スキーマに合う JSON を生成できませんでした。最後のエラー: {last_error}"
    )


@app.post("/parse")
async def parse_invoice(file: UploadFile = File(...)) -> dict[str, Any]:
    content = await file.read()
    filename = (file.filename or "").lower()

    try:
        if filename.endswith(".pdf"):
            doc = fitz.open(stream=content, filetype="pdf")
            text = "\n".join(
                f"--- Page {i + 1} ---\n{page.get_text('text')}"
                for i, page in enumerate(doc)
            )
        elif filename.endswith((".xlsx", ".xls")):
            import openpyxl
            wb = openpyxl.load_workbook(io.BytesIO(content), data_only=True)
            rows = [
                ",".join(str(c) if c is not None else "" for c in row)
                for ws in wb.worksheets
                for row in ws.iter_rows(values_only=True)
            ]
            text = "\n".join(rows)
        elif filename.endswith((".docx", ".doc")):
            import mammoth
            result = mammoth.extract_raw_text(io.BytesIO(content))
            text = result.value
        elif filename.endswith((".jpg", ".jpeg", ".png", ".webp")):
            raise HTTPException(
                status_code=400,
                detail="画像ファイルは現在未対応です（テキスト専用モデル使用中）",
            )
        else:
            text = content.decode("utf-8", errors="replace")

        if len(text) > MAX_CHARS:
            text = text[:MAX_CHARS]

        return extract_with_validation(text)

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
