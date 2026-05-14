# costora-infra

Terraform で管理する AWS インフラ。ap-northeast-1 (東京) リージョン。

## 主要な意思決定

詳細は `docs/adr/` を参照。変更時は関連ADRを確認・更新すること。

| 決定 | 結論 | ADR |
|---|---|---|
| LLM基盤 | Ollama llama3.1:8b（Bedrock利用不可） | [ADR 001](docs/adr/001-ollama-over-bedrock.md) |
| EC2構成 | nginx/FastAPI/Ollama を1台に同居（コスト優先） | [ADR 002](docs/adr/002-single-ec2-colocation.md) |
| DNS管理 | Route53（Terraform統合・certbot自動化） | [ADR 003](docs/adr/003-route53-dns-management.md) |
| EC2アクセス | SSM Session Manager（SSH不要） | [ADR 004](docs/adr/004-ssm-over-ssh.md) |
| インスタンス種別 | オンデマンド（スポットクォータが0のため） | [ADR 005](docs/adr/005-ondemand-over-spot.md) |
| GPU vs CPU | CPU推論 m5.xlarge（Gファミリークォータが0のため暫定） | [ADR 006](docs/adr/006-cpu-inference-temporary.md) |

## アーキテクチャ概要

```
Vercel (Next.js)
    ↓ HTTPS / X-Api-Key ヘッダー
inference.patrae.net (Route53 A → EIP)
    ↓
EC2 m5.xlarge オンデマンドインスタンス（CPU推論・暫定）
    ├── nginx :443        ← TLS終端 + APIキー認証
    ├── FastAPI :8000     ← PDF解析 + Ollama呼び出し
    └── Ollama :11434     ← llama3.1:8b 推論
```

## 主要リソース

| リソース | 用途 |
|---|---|
| `aws_instance.ollama` | 推論サーバー (m5.xlarge、CPU推論・暫定) |
| `aws_eip.ollama` | 固定パブリックIP |
| `aws_route53_zone.patrae` | patrae.net DNS管理 |
| `aws_route53_record.inference` | inference.patrae.net → EIP |
| `aws_dynamodb_table.keys` | APIキー管理 |
| `aws_s3_bucket.invoice` | 請求書ファイル保存 |
| `random_password.inference_api_key` | nginx APIキー（自動生成） |

## デプロイ手順

```bash
# 認証（SSO未設定の場合）
eval "$(aws configure export-credentials --format env)"

terraform init
terraform plan
terraform apply
```

## apply 後の手動ステップ

1. **Squarespace NS変更**（初回のみ）
   ```bash
   terraform output route53_name_servers
   ```
   出力された4件のNSをSquarespaceのネームサーバーに設定する。

2. **TLS設定**（DNS伝播後）
   自動で実行される。失敗した場合はSSM経由で実行:
   ```bash
   aws ssm start-session --target $(terraform output -raw ollama_instance_id)
   sudo /opt/setup-tls.sh
   ```

3. **Vercel環境変数の設定**
   ```bash
   terraform output -raw inference_api_key
   ```
   - `PARSE_API_URL=https://inference.patrae.net`
   - `INFERENCE_API_KEY=<上記の値>`

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

`setup_tls.sh` と `userdata.sh` は Terraform `templatefile()` で処理されるため、nginx変数は `$$host` のように `$$` でエスケープしている。

## 注意点

- `inference_api_key` は State に保存される。ローテーションは `terraform apply -replace="random_password.inference_api_key"`
- `ollama pull llama3.1:8b` は起動時に実行されるため、初回起動は10〜15分程度かかる
