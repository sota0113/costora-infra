# ADR 003: DNS管理を Squarespace から Route53 に移行

**Status**: Adopted  
**Date**: 2026-05

## Context

ドメイン `patrae.net` は Squarespace で取得・管理していた。`inference.patrae.net` のAレコードを作成し、Let's Encrypt の DNS-01 チャレンジを自動化するために DNS 管理をどこで行うかを検討した。

選択肢:
1. Squarespace で Aレコードを手動追加し、certbot の HTTP-01 チャレンジを使う
2. `inference.patrae.net` サブドメインのみ Route53 に委任（Option A）
3. `patrae.net` 全体を Route53 に移行（Option B）

## Decision

`patrae.net` 全体を Route53 に移行する（Option B）。

- Terraform で `aws_route53_zone` を管理し、DNS レコードをコードで管理
- certbot-dns-route53 プラグインにより、DNS-01 チャレンジが EC2 の IAM ロール経由で完全自動化
- EC2 の IAM ロールに最小限の Route53 権限（`ChangeResourceRecordSets` 等）を付与

SquarespaceのネームサーバーをRoute53のNSに変更することで移行完了。

## Consequences

- **運用の一元化**: DNS・証明書・インフラがすべて Terraform で管理される
- **証明書自動更新**: certbot の systemd timer により cron で自動更新。ポート80不要（DNS-01）
- **Squarespace 依存の解消**: DNS に関しては Squarespace を参照する必要がなくなる
- **移行コスト**: 初回のみ Squarespace での NS 変更作業が必要。既存レコード（ウェブサイト等）の移行も必要
- **Route53 コスト**: ホストゾーン $0.50/月 + クエリ料金（微小）
