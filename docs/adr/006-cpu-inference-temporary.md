# ADR 006: GPU インスタンスの代わりに CPU インスタンスで推論（暫定）

**Status**: Superseded by [ADR 008](008-bedrock-migration.md)  
**Date**: 2026-05

## Context

G ファミリーの vCPU クォータが 0 のため、スポット・オンデマンドともに g4dn.xlarge の起動に失敗した（ADR 005 参照）。Service Quotas への申請中、推論サーバーを動かすための暫定対応が必要。

## Decision

GPU インスタンスの代わりに `m5.xlarge`（4 vCPU / 16 GB RAM）を使用する。

- AMI: Deep Learning AMI → Amazon Linux 2023 標準 AMI に変更
- llama3.1:8b は CPU でも動作する（Ollama が自動で CPU 推論にフォールバック）
- GPU クォータが承認され次第 g4dn.xlarge + Deep Learning AMI に戻す

## Consequences

- **推論速度**: GPU（数秒）→ CPU（1〜3分/リクエスト）に低下
- **コスト**: g4dn.xlarge $0.526/h → m5.xlarge $0.192/h に削減
- **クォータ不要**: 標準ファミリーはデフォルトクォータで起動可能
- **機能は同じ**: FastAPI・nginx・Ollama の構成は変わらない
