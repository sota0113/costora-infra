# ADR 007: SES メール転送による請求書自動取り込み

**日付**: 2026-06-17
**ステータス**: 承認済み

## 背景

現状、PDFインボイスは Settings 画面から手動でアップロードする必要がある。
SaaS の請求書はメールで届くことが多いため、メールを転送するだけで自動登録できる仕組みを作る。

## 決定

### 受信リージョン: us-east-1

AWS SES のメール受信（Inbound）は以下のリージョンのみ対応:
- us-east-1 (N. Virginia)
- us-west-2 (Oregon)
- eu-west-1 (Ireland)
- ap-southeast-2 (Sydney)

**東京（ap-northeast-1）は未対応**。コスト管理の主リージョンは ap-northeast-1 だが、SES 受信のみ us-east-1 に配置する。Lambda も同リージョン。

### メールアドレス形式

```
invoice-{itemId}@mail.costora.net
```

- `itemId`: CostItem の UUID（DynamoDB に保存済みの識別子）
- `mail.costora.net` 宛のMXレコードを SES inbound endpoint に設定

**別案と却下理由:**
- `{tenantKey}+{itemId}@...` → tenantKey にコロン（`:`）が含まれるためメールのlocal partとして無効
- ランダムトークン → itemId から導出できないため別途マッピングテーブルが必要になり複雑

### テナント解決方法

Lambda はメールの To ヘッダーから itemId のみ知ることができる。tenantKey（DynamoDB のパーティションキー）は別途解決が必要。

**解決策**: DynamoDB の既存テーブルに `email_aliases` 予約レコードを追加。

```
{ tenantKey: "email_aliases", service: "{itemId}", value: "{actualTenantKey}" }
```

- invoice アイテム作成時に登録
- invoice アイテム削除時に削除

### Lambda → Vercel 連携

Lambda（us-east-1）は FastAPI（ap-northeast-1 EC2）に直接アクセスできない（VPC外）。
Vercel の Next.js API エンドポイント `/api/webhook/ses-invoice` を経由する。

```
Lambda → POST /api/webhook/ses-invoice (Vercel)
    ↓
Next.js → FastAPI /parse → DynamoDB invoiceEntries 更新
```

認証: `X-Webhook-Secret` ヘッダー（Terraform で生成した `ses_webhook_secret`）

**別案と却下理由:**
- Lambda → FastAPI 直接 → FastAPI は VPC 外からアクセスできるが、DynamoDB への書き込みロジックが FastAPI に漏れる。責務分離のため Vercel 経由が望ましい。

### メール保存期間

S3 バケットのライフサイクルポリシーで 7 日後に自動削除。個人情報・機密情報を含む請求書を最小限の期間のみ保持する。

## アーキテクチャ図

```
転送メール → SES (us-east-1)
    ↓ S3 PutObject
s3://costora-ses-emails-{accountId}/incoming/
    ↓ S3 Event
Lambda (us-east-1) costora-ses-invoice-handler
    ↓ parse To header → itemId
    ↓ extract attachment (PDF/xlsx/docx)
    ↓ POST { itemId, filename, fileBase64 } + X-Webhook-Secret
Vercel /api/webhook/ses-invoice
    ↓ lookup email_aliases → tenantKey
    ↓ POST multipart/form-data
inference.costora.net/parse (FastAPI + Ollama)
    ↓ { fields: [...] }
DynamoDB: item.invoiceEntries += { month, amount }
```

## 結果

- 請求書メールを `invoice-{itemId}@mail.costora.net` に転送するだけで自動登録
- コスト: SES受信 $0.10/1000通、Lambda 無料枠内、実質無料
- S3 保存期間 7 日で個人情報リスクを最小化
