# ADR 004: EC2 アクセスに SSH の代わりに SSM Session Manager を使用

**Status**: Adopted  
**Date**: 2026-05

## Context

EC2 インスタンスへのアクセス手段として SSH と AWS Systems Manager Session Manager を比較した。

## Decision

AWS Systems Manager (SSM) Session Manager を採用する。

- セキュリティグループにポート22 (SSH) を追加しない
- EC2 の IAM ロールに `AmazonSSMManagedInstanceCore` ポリシーをアタッチ
- アクセスは `aws ssm start-session --target <instance-id>` で行う

## Consequences

- **セキュリティ向上**: ポート22の開放が不要。SSHキーの管理・漏洩リスクがない
- **IAM統合**: AWS IAMでアクセス制御できる。セッションログをCloudTrailに記録可能
- **踏み台不要**: VPC外からでも IAM 権限があれば直接接続できる
- **依存**: AWS SSM Agent が EC2 上で動作している必要がある（Deep Learning AMI には標準インストール済み）
