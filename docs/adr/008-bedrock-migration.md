# ADR 008: Ollama セルフホストから Amazon Bedrock へ移行

**Status**: Adopted  
**Date**: 2026-06

## Context

ADR 001 でアカウント制約により断念した Bedrock が、2026-06 時点で利用可能になっていることを確認した。
`us-east-1` リージョンの US クロスリージョン推論プロファイル (`us.` プレフィックス) が ACTIVE 状態で、API 接続テストも成功。

利用可能な主なモデル:
- `us.anthropic.claude-haiku-4-5-20251001-v1:0` — 高速・低コスト
- `us.anthropic.claude-sonnet-4-6` — 最新 Sonnet

## Decision

推論バックエンドを Ollama セルフホストから Amazon Bedrock に切り替える。

- **モデル**: `us.anthropic.claude-haiku-4-5-20251001-v1:0`（高速・低コスト優先）
- **リージョン**: `us-east-1`（US クロスリージョン推論プロファイルの要件）
- **EC2**: GPU 不要となるため g4dn.xlarge → t3.medium に縮小（PyMuPDF の PDF 処理メモリを考慮し small ではなく medium）
- **AMI**: Deep Learning AMI → Amazon Linux 2023 標準 AMI に変更
- **ボリューム**: モデルウェイト不要のため 50GB → 30GB に縮小（AL2023 AMI スナップショットの最小要件が 30GB のため 20GB は不可）
- **IAM**: EC2 インスタンスロールに `bedrock:InvokeModel` 権限を付与

## VPC Endpoint について

EC2 は ap-northeast-1、Bedrock は us-east-1 のクロスリージョン呼び出しになるため、VPC エンドポイント（リージョン内専用）は使用不可。EC2 の EIP 経由でインターネット越しに HTTPS 接続する。TLS 暗号化と IAM 認証で通信は保護される。

## Consequences

- **コスト**: EC2 $0.526/h (g4dn.xlarge) → $0.0416/h (t3.medium) に削減。Bedrock 推論コストが加算されるが、呼び出し頻度が低ければ大幅な削減になる
- **精度**: llama3.1:8b → Claude Haiku 4.5 に向上
- **レイテンシ**: ローカル GPU 推論と比べ若干増加するが、Haiku は API レスポンスが高速
- **可用性**: Bedrock は AWS マネージドサービスのため、EC2 障害に依存しない
- **依存**: AWS Bedrock サービスへの依存が生まれる（ap-northeast-1 の Bedrock が利用可能になれば、同一リージョンに統一できる）
