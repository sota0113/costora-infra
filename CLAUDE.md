# costora-infra

Terraform で管理する AWS インフラ。ap-northeast-1 (東京) リージョン。

## 主要な意思決定

詳細は `docs/adr/` を参照。変更時は関連ADRを確認・更新すること。

| 決定 | 結論 | ADR |
|---|---|---|
| LLM基盤 | Amazon Bedrock claude-haiku-4-5（us-east-1） | [ADR 008](docs/adr/008-bedrock-migration.md) |
| EC2構成 | nginx/FastAPI を1台に同居（コスト優先） | [ADR 002](docs/adr/002-single-ec2-colocation.md) |
| DNS管理 | Route53（Terraform統合・certbot自動化） | [ADR 003](docs/adr/003-route53-dns-management.md) |
| EC2アクセス | SSM Session Manager（SSH不要） | [ADR 004](docs/adr/004-ssm-over-ssh.md) |
| インスタンス種別 | オンデマンド（スポットクォータが0のため） | [ADR 005](docs/adr/005-ondemand-over-spot.md) |
| GPU vs CPU | Bedrock移行によりGPU不要、t3.small を使用 | [ADR 008](docs/adr/008-bedrock-migration.md) |
| SESメール転送 | us-east-1 受信 + Lambda → Vercel Webhook | [ADR 007](docs/adr/007-ses-email-forwarding.md) |

## アーキテクチャ概要

```
メール転送
    ↓
SES (us-east-1) → S3 → Lambda (us-east-1)
    ↓ POST /api/webhook/ses-invoice
Vercel (Next.js)
    ↓ HTTPS / X-Api-Key ヘッダー
inference.costora.net (Route53 A → EIP)
    ↓
EC2 t3.small オンデマンドインスタンス（Amazon Linux 2023）
    ├── nginx :443        ← TLS終端 + APIキー認証
    └── FastAPI :8000     ← PDF解析 + Bedrock呼び出し
                                    ↓ HTTPS (インターネット経由)
                          Amazon Bedrock us-east-1
                              claude-haiku-4-5 推論
```

## 主要リソース

| リソース | 用途 |
|---|---|
| `aws_instance.ollama` | 推論サーバー (t3.small、nginx + FastAPI) |
| `aws_eip.ollama` | 固定パブリックIP |
| `aws_route53_zone.costora` | costora.net DNS管理 |
| `aws_route53_record.inference` | inference.costora.net → EIP |
| `aws_dynamodb_table.keys` | APIキー管理 |
| `aws_s3_bucket.invoice` | 請求書ファイル保存 |
| `random_password.inference_api_key` | nginx APIキー（自動生成） |
| `aws_ses_domain_identity.costora` | SES ドメイン認証 (us-east-1) |
| `aws_s3_bucket.ses_emails` | 受信メール一時保存 (us-east-1、7日で自動削除) |
| `aws_lambda_function.ses_invoice` | メール → Webhook 転送 Lambda (us-east-1) |
| `random_password.ses_webhook_secret` | Lambda ↔ Vercel 間の共有シークレット |

## デプロイ手順

```bash
# 認証（SSO未設定の場合）
eval "$(aws configure export-credentials --format env)"

terraform init
terraform plan
terraform apply
```

## apply 後の手動ステップ

1. **NS設定**（初回のみ）
   ```bash
   terraform output route53_name_servers
   ```
   出力された4件のNSをcostora.netのドメインレジストラに設定する。

2. **TLS設定**（DNS伝播後）
   自動で実行される。失敗した場合はSSM経由で実行:
   ```bash
   aws ssm start-session --target $(terraform output -raw ollama_instance_id)
   sudo /opt/setup-tls.sh
   ```

3. **Vercel環境変数の設定**
   ```bash
   terraform output -raw inference_api_key
   terraform output -raw ses_webhook_secret
   ```
   - `PARSE_API_URL=https://inference.costora.net`
   - `INFERENCE_API_KEY=<inference_api_key の値>`
   - `SES_WEBHOOK_SECRET=<ses_webhook_secret の値>`

## EC2へのアクセス（SSM）

```bash
aws ssm start-session --target $(terraform output -raw ollama_instance_id)
```

SSH不要。ポート22は開放していない。

## scripts/ ディレクトリ

| ファイル | 説明 |
|---|---|
| `userdata.sh` | EC2起動時のセットアップスクリプト（Terraformテンプレート） |
| `inference_api.py` | FastAPI アプリ本体 |
| `setup_tls.sh` | Let's Encrypt TLS取得スクリプト（Terraformテンプレート） |
| `ses_invoice_handler.py` | SES受信メール処理 Lambda 関数 |

`setup_tls.sh` と `userdata.sh` は Terraform `templatefile()` で処理される。nginx変数（`$host` など）はそのまま記述してよい（`$` に `{` が続かない場合は Terraform がテンプレートとして解釈しない）。Terraform 変数は `${var_name}` 形式のみ展開される。

## 注意点

- `inference_api_key` は State に保存される。ローテーションは `terraform apply -replace="random_password.inference_api_key"`
- Bedrock 推論は us-east-1 へのクロスリージョン呼び出し（VPC エンドポイント不可）。EIP 経由 HTTPS で接続
- EC2 の IAM ロールに `bedrock:InvokeModel` 権限を付与済み（Instance Profile 経由で認証、env の AWS キー不要）
