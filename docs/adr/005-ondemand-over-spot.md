# ADR 005: スポットインスタンスからオンデマンドインスタンスに変更

**Status**: Adopted  
**Date**: 2026-05

## Context

当初 g4dn.xlarge をスポットインスタンス（`aws_spot_instance_request`）で構築することでコスト削減（~$0.16/h）を図っていた。

しかし `terraform apply` 時に以下のエラーが発生し、デプロイが失敗した:

```
Error: requesting EC2 Spot Instance: operation error EC2: RequestSpotInstances,
api error MaxSpotInstanceCountExceeded: Max spot instance count exceeded
```

原因: AWS アカウントにおける G ファミリーのスポットインスタンスクォータがデフォルト 0 vCPU。Service Quotas から申請すれば引き上げ可能だが、即時対応のためオンデマンドに切り替えた。

## Decision

`aws_spot_instance_request` → `aws_instance`（オンデマンド）に変更する。

## Consequences

- **コスト増**: ~$0.16/h（スポット）→ ~$0.526/h（オンデマンド）
- **可用性向上**: スポット中断リスクがなくなる
- **即時デプロイ**: クォータ申請待ちなしに起動できる
- **将来**: Service Quotas でクォータを引き上げた後、スポットに戻すことも可能
