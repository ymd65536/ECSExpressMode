# 【AWS】検証！Amazon ECS Express ModeとCode Buildでデプロイ

## はじめに

この記事では「この前リリースされた機能って実際に動かすとどんな感じなんだろう」とか「もしかしたら内容次第では使えるかも？？」などAWSサービスの中でも特定の機能にフォーカスして検証していく記事です。

主な内容としては実践したときのメモを中心に書きます。（忘れやすいことなど）
誤りなどがあれば書き直していく予定です。

今回はAmazon ECS Express Mode（以下、本文ではECS Express Mode）を検証してみます。

## ECSのデプロイっって地味に面倒かもしれねぇ

これまで何度もECSのデプロイを経験してきましたが、タスク定義の作成やサービスの更新など、手順が多くて面倒に感じることがありました。
個人的にはタスク定義の管理はとても面倒で、特に小規模なプロジェクトや頻繁にデプロイが必要な場合には、その手間が負担になることもあります。

ECS Express Modeではこれらの手順を簡素化し、より迅速にデプロイを行えるようになりました。
説明を聞いてもなんだかピンとこないと思うので実際にやってみましょう。

## おおまかな流れ

まずはECS Express Modeを使ったデプロイの大まかな流れを確認しましょう。
今回はECS Express Modeは事前にコンテナイメージがECRにプッシュされていることを前提としていますので、GitHubのソースを使ってCode Buildでイメージをビルドし、ECRにプッシュするところから始めます。

具体的には以下の通りです。

- AWSとGitHubでコネクションを作成する
- コードをプッシュしてCode Buildをキック
  - イメージをビルドされてECRにプッシュされます
- Optional: デフォルトVPCの作成
  - デフォルトVPCが存在しない場合は作成します
- ECRのイメージを使ってデプロイ

なお、ECS Expressではdefault VPCを使用します。default VPCが存在しない場合は作成時に以下のエラーが発生しますので注意してください。

```
ServerException
An unexpected error occurred: No default VPC found in the region
```

## セットアップ

## Optional: デフォルトVPCの作成

注意事項

- デフォルトVPCは1つのリージョンにつき1つのみ作成できます
- 既にデフォルトVPCが存在する場合は、以下のエラーが表示されます：
  ```
  An error occurred (DefaultVpcAlreadyExists) when calling the CreateDefaultVpc operation: A Default VPC already exists for this account in this region.
  ```
- デフォルトVPCは以下の特徴があります：
  - CIDR ブロック: `172.31.0.0/16`
  - 各アベイラビリティーゾーンにデフォルトサブネットが自動作成されます
  - インターネットゲートウェイが自動的にアタッチされます
  - デフォルトのセキュリティグループとネットワークACLが作成されます


### デフォルトVPCの作成

デフォルトVPCが存在しない場合は、以下のコマンドで作成できます。

```bash
aws ec2 create-default-vpc
```

正常に作成されると、以下のようなレスポンスが返されます：

```json
{
    "Vpc": {
        "OwnerId": "123456789012",
        "InstanceTenancy": "default",
        "Ipv6CidrBlockAssociationSet": [],
        "CidrBlockAssociationSet": [
            {
                "AssociationId": "vpc-cidr-assoc-XXXXXXXX",
                "CidrBlock": "172.31.0.0/16",
                "CidrBlockState": {
                    "State": "associated"
                }
            }
        ],
        "IsDefault": true,
        "Tags": [],
        "VpcId": "vpc-XXXXXXXXX",
        "State": "pending",
        "CidrBlock": "172.31.0.0/16",
        "DhcpOptionsId": "dopt-XXXXXXXX"
    }
}
```

### デフォルトVPCにNameタグを追加

作成直後のデフォルトVPCにはNameタグが設定されていないため、以下のコマンドで追加します：

```bash
# VPC IDを取得
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)

# Nameタグを追加
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=default
```

### デフォルトVPCの確認

作成されたデフォルトVPCを確認するには、以下のコマンドを実行します：

```bash
aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].IsDefault"
```

実行結果

```
true
```

### AWSとGitHubのコネクション作成

### コードをプッシュしてCode Buildをキック

## ECRのイメージを使ってデプロイ

## まとめ

## AWS CLI インストールと SSO ログイン手順 (Linux環境)

このガイドでは、Linux環境でAWS CLIをインストールし、AWS SSOを使用してログインするまでの手順を説明します。

## 前提条件

- Linux環境（Ubuntu、CentOS、Amazon Linux等）
- インターネット接続
- 管理者権限（sudoが使用可能）
- AWS SSO が組織で設定済み
- Python 3.12.1

## AWS CLI のインストール

### 公式インストーラーを使用（推奨）

最新版のAWS CLI v2を公式インストーラーでインストールします。

```bash
# 1. インストーラーをダウンロード
curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip"

# 2. unzipがインストールされていない場合はインストール
sudo apt update && sudo apt install unzip -y  # Ubuntu/Debian系
# または
sudo yum install unzip -y                     # CentOS/RHEL系

# 3. ダウンロードしたファイルを展開
unzip awscliv2.zip

# 4. インストール実行
sudo ./aws/install

# 5. インストール確認
aws --version

# ダウンロードしたzipファイルと展開したディレクトリを削除してクリーンアップします。
rm  "awscliv2.zip"

# 解凍したディレクトリを削除
rm -rf aws
```

## AWS SSO の設定とログイン

### 1. AWS SSO の設定

AWS SSOを使用するための初期設定を行います。

```bash
aws configure sso
```

設定時に以下の情報の入力が求められます：

- **SSO start URL**: 組織のSSO開始URL（例：`https://my-company.awsapps.com/start`）
- **SSO Region**: SSOが設定されているリージョン（例：`us-east-1`）
- **アカウント選択**: 利用可能なAWSアカウントから選択
- **ロール選択**: 選択したアカウントで利用可能なロールから選択
- **CLI default client Region**: デフォルトのAWSリージョン（例：`ap-northeast-1`）
- **CLI default output format**: 出力形式（`json`、`text`、`table`のいずれか）
- **CLI profile name**: プロファイル名（`default`とします。）

### 2. AWS SSO ログイン

設定完了後、以下のコマンドでログインを実行します。

```bash
aws sso login
```

ログイン時の流れ：
1. コマンド実行後、ブラウザが自動的に開きます
2. AWS SSOのログインページが表示されます
3. 組織のIDプロバイダー（例：Active Directory、Okta等）でログイン
4. 認証が成功すると、ターミナルに成功メッセージが表示されます

### 3. ログイン状態の確認

認証情報を確認します。

```bash
aws sts get-caller-identity
```

正常にログインできている場合、以下のような情報が表示されます：

```json
{
    "UserId": "AROAXXXXXXXXXXXXXX:username@company.com",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/RoleName/username@company.com"
}
```

## トラブルシューティング

### よくある問題と解決方法

#### 1. ブラウザが開かない場合

```bash
# 手動でブラウザを開く場合のURL確認
aws sso login --no-browser
```

表示されたURLを手動でブラウザで開いてください。

#### 2. セッションが期限切れの場合

```bash
# 再ログイン
aws sso login
```

#### 4. プロキシ環境での設定

プロキシ環境の場合、以下の環境変数を設定してください：

```bash
export HTTP_PROXY=http://proxy.company.com:8080
export HTTPS_PROXY=http://proxy.company.com:8080
export NO_PROXY=localhost,127.0.0.1,.company.com
```

## セキュリティのベストプラクティス

1. **定期的な認証情報の更新**: SSOセッションには有効期限があります。定期的に再ログインを行ってください。

2. **最小権限の原則**: 必要最小限の権限を持つロールを使用してください。

3. **プロファイルの分離**: 本番環境と開発環境で異なるプロファイルを使用してください。

4. **ログアウト**: 作業終了時は適切にログアウトしてください：
   ```bash
   aws sso logout --profile <プロファイル名>
   ```

## 参考リンク

- [AWS CLI ユーザーガイド](https://docs.aws.amazon.com/cli/latest/userguide/)
- [AWS SSO ユーザーガイド](https://docs.aws.amazon.com/singlesignon/latest/userguide/)
- [AWS CLI インストールガイド](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
