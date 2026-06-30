# ADR 009: EC2 を t3.medium から t3.micro へさらに縮小

**Status**: Adopted
**Date**: 2026-06

## Context

ADR 008 で GPU 不要となり g4dn.xlarge → t3.medium に縮小したが、当時は「PyMuPDF の PDF 処理メモリを考慮し small ではなく medium」という見積もりに基づく判断であり、実測には基づいていなかった。

実際のワークロードは以下の通り低負荷:
- uvicorn はシングルワーカーで起動（`userdata.sh` に `--workers` 指定なし）
- リクエストは「メール転送による請求書1件のパース」または「ダッシュボードからの手動パース」のみで、頻度は低い
- PDF は請求書（数ページ程度）が中心で、大容量ドキュメントは想定していない
- CPU/メモリ集約的な処理（旧 Ollama 推論）は Bedrock 移行により既に EC2 から無くなっている

## Decision

`aws_instance.ollama` の `instance_type` を `t3.medium` (4GB RAM) から `t3.micro` (1GB RAM) に変更する。

- `t3.nano` (0.5GB) は OS + nginx + Python ランタイム（FastAPI, boto3, PyMuPDF, openpyxl, mammoth 等のロードだけで数百MB）の起動だけでメモリを使い切る可能性が高いため除外し、実用上の最小である `t3.micro` を選定した。
- `inference.service` は `Restart=always` のため、万一 OOM でプロセスが落ちても自動復旧する。
- ボリューム (30GB gp3) は AL2023 AMI スナップショットの最小要件のため変更なし。

## Consequences

- **コスト**: EC2 $0.0416/h (t3.medium) → 約 $0.0104/h (t3.micro) に削減（約75%減）
- **リスク**: 実測なしでの変更のため、高負荷時（同時リクエストや大きめのPDF）に OOM が発生する可能性がある。`Restart=always` により可用性は維持されるが、当該リクエストは失敗する
- **モニタリング**: 現状 CloudWatch Agent 未導入のためメモリ使用率は見えない。OOM が頻発するようであれば `t3.small` への引き上げ、または CloudWatch Agent 導入によるメモリ監視を検討する
