# ADR 002: nginx・FastAPI・Ollama を単一EC2に同居

**Status**: Adopted  
**Date**: 2026-05

## Context

推論サーバーの構成として、以下のコンポーネントが必要:
- Ollama（GPU推論）
- FastAPI（PDF解析・Ollama呼び出し）
- nginx（TLS終端・APIキー認証・リバースプロキシ）

これらを別インスタンスに分離するか、1台に同居させるかを検討した。

## Decision

コスト最優先で単一の g4dn.xlarge オンデマンドインスタンスに全コンポーネントを同居させる。

- nginx: ポート80/443でリクエストを受け、FastAPIへプロキシ
- FastAPI: `localhost:8000` でバインド（外部非公開）
- Ollama: `localhost:11434` でバインド（外部非公開）

## Consequences

- **コスト削減**: 1台分のインスタンス料金で済む
- **低レイテンシ**: FastAPI → Ollama 間がローカル通信
- **セキュリティ**: FastAPI と Ollama は外部から直接アクセス不可。nginx の APIキー認証が唯一の入口
- **スケーラビリティ**: 単一インスタンスのため水平スケールが難しい。負荷増大時はコンポーネント分離が必要
- **障害分離**: Ollama がクラッシュすると FastAPI・nginx も同一インスタンスの影響を受ける
