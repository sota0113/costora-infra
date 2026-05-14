# ADR 001: Amazon Bedrock の代わりに Ollama をセルフホスト

**Status**: Adopted  
**Date**: 2026-05

## Context

インボイス解析にLLMを利用する必要があった。当初は Amazon Bedrock（`anthropic.claude-3-5-sonnet`）を採用する方針だったが、利用しているAWSアカウントでは Bedrock が有効化できない状態にあった。

試みた対応:
- モデルID を `anthropic.claude-3-5-sonnet-20241022-v2:0` → クロスリージョン推論プロファイル `ap.anthropic.claude-3-5-sonnet-20241022-v2:0` に変更したが、アカウント側の制約で解消しなかった。

## Decision

Ollama をセルフホストした EC2 上で `llama3.1:8b` モデルを動かす構成に切り替える。

- GPU付きインスタンス (g4dn.xlarge / NVIDIA T4) をオンデマンドで調達
- Ollama は EC2 起動時の user_data で自動インストール・モデルプル
- FastAPI で Ollama HTTP API をラップし、PDF抽出・スキーマ検証を担わせる

## Consequences

- **コスト**: オンデマンド g4dn.xlarge（~$0.526/h）が常時稼働コストになる。当初スポット（~$0.16/h）を想定していたが、G ファミリーのスポットクォータがデフォルト 0 のため断念（ADR 005 参照）
- **精度**: `llama3.1:8b` は Claude 3.5 Sonnet より能力が低い。解析精度の低下リスクがある
- **テキスト専用**: `llama3.1:8b` は画像・PDF を直接受け付けないため、FastAPI 側でテキスト抽出が必要
- **可用性**: オンデマンドのため中断リスクなし
- **将来**: Bedrock が利用可能になれば、FastAPI を差し替えるだけで移行できる設計にしている
