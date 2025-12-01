# 【AWS】検証！Amazon ECS Express ModeとCode Buildでデプロイ
## この記事のポイント

- Amazon ECS Express Modeをハンズオンしたうえで課題となる点を書いているよ

## はじめに

この記事では「この前リリースされた機能って実際に動かすとどんな感じなんだろう」とか「もしかしたら内容次第では使えるかも？？」などAWSサービスの中でも特定の機能にフォーカスして検証していく記事です。

主な内容としては実践したときのメモを中心に書きます。（忘れやすいことなど）
誤りなどがあれば書き直していく予定です。

今回はAmazon ECS Express Mode（以下、本文ではECS Express Mode）を検証してみます。

参考リンク

- [Announcing Amazon ECS Express Mode](https://aws.amazon.com/jp/about-aws/whats-new/2025/11/announcing-amazon-ecs-express-mode/)
- [Build production-ready applications without infrastructure complexity using Amazon ECS Express Mode](https://aws.amazon.com/jp/blogs/aws/build-production-ready-applications-without-infrastructure-complexity-using-amazon-ecs-express-mode/)
- [Benefits of Amazon ECS Express Mode services](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-overview.html)

## ECSのデプロイっって地味に面倒かもしれねぇ

これまで何度もECSのデプロイを経験してきましたが、手順が多くて面倒に感じることがありました。具体的には以下のとおりです。

- クラスターの作成
- タスク定義の作成
- タスク定義の更新
- サービスの更新

特に小規模なプロジェクトや頻繁にデプロイが必要な場合には、その手間が負担になることもあります。
ちなみにフロントエンドあるいはバックエンドで使うかどうかで変わってくる部分はあるかもしれませんが、ECSでの一般的なデプロイ手順は以下の通りです。

1. dockerfileからコンテナイメージのビルド、ECRへのプッシュ
2. タスク定義の作成または更新
3. サービスの作成または更新
4. デプロイの確認、ヘルスチェック

ECSの前段にALBを配置する場合は、ALBのリスナーやターゲットグループの設定も必要になります。
多くはAWS CDKやTerraformなどのIaCツールを使って自動化していると思いますが、手動で行う場合は特に面倒に感じます。
※筆者の場合はマルチリージョン構成のECSをAWS CDKを使って自動化していたりします。

ECS Express Modeではこれらの手順を簡素化し、より迅速にデプロイを行えるようになりました。
説明を聞いてもなんだかピンとこないと思うので実際にやってみましょう。

## おおまかな流れ

まずはECS Express Modeを使ったデプロイの大まかな流れを確認しましょう。
今回はECS Express Modeは事前にコンテナイメージがECRにプッシュされていることを前提としていますので、GitHubのソースを使ってCode Buildでイメージをビルドし、ECRにプッシュするところから始めます。

具体的には以下の通りです。

- Optional: デフォルトVPCの作成
  - デフォルトVPCが存在しない場合は作成します
- CodeBuildを構築してイメージをビルド
  - イメージをビルドしてECRにプッシュされます
- ECRのイメージを使ってECS Expressによるデプロイ

なお、ECS Expressではdefault VPCを使用します。default VPCが存在しない場合は作成時に以下のエラーが発生しますので注意してください。

```
ServerException
An unexpected error occurred: No default VPC found in the region
```

## セットアップ

では、事前準備を進めていきましょう。

## Optional: デフォルトVPCの作成

まずはdefault VPCが存在しない人のための手順を紹介しようと思いますが、注意事項がありますので確認します。
※すでにAWSアカウント内にdefault VPCが存在する場合はこのセクションはスキップして構いません。

AWS CloudShellを使用してVPCを作成します。もちろん、VPCを作成するのでVPCを作成するための権限が必要です。
今回はAdministratorAccessを持つユーザーでCloudShellにログインしています。

default VPCには以下の特徴があります。

- defaultVPCは1つのリージョンにつき1つのみ作成可能
- 既にデフォルトVPCが存在する場合は、以下のエラーが表示されます：
  ```
  An error occurred (DefaultVpcAlreadyExists) when calling the CreateDefaultVpc operation: A Default VPC already exists for this account in this region.
  ```
- default VPCは以下の特徴があります：
  - CIDR ブロック: `172.31.0.0/16`
  - 各アベイラビリティーゾーンにデフォルトサブネットが自動作成されます
  - インターネットゲートウェイが自動的にアタッチされます
  - デフォルトのセキュリティグループとネットワークACLが作成されます

### デフォルトVPCの作成

では実際にデフォルトVPCを作成してみましょう。
デフォルトVPCが存在しない場合は、[AWS CLIのドキュメント](https://docs.aws.amazon.com/cli/latest/reference/ec2/create-default-vpc.html)を参考に以下のコマンドで作成できます。

```bash
aws ec2 create-default-vpc
```

正常に作成されると、以下のようなレスポンスが返されます。

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

作成直後のデフォルトVPCにはNameタグが設定されていないため、以下のコマンドで追加します。

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

### リポジトリをクローンする

セットアップするために、リポジトリをクローンします。

```bash
git clone https://github.com/ymd65536/ECSExpressMode.git
```

このリポジトリに今回のセットあぷに必要なファイルが含まれています。
ディレクトリを変更します。

```bash
cd ECSExpressMode
```

## CodeBuildを構築してイメージをビルド

ではここから、ECS Express Modeで使用するコンテナイメージをCodeBuildでビルドしてECRにプッシュする手順を紹介します。
今回はCloudFormationテンプレートを使用してCodeBuildのプロジェクトを作成し、ビルドを実行します。

以下のコマンドでCloudFormationスタックをデプロイします。

```bash
aws cloudformation deploy --template-file image_build.yml --stack-name ecs-express-image-build --capabilities CAPABILITY_NAMED_IAM
```

スタックのデプロイが完了したら、以下のコマンドでビルドを開始します。`BUILD_ID`という変数の後ろから最後までのコマンドはビルドの進捗をポーリングしてステータスを表示するためのものです。

```bash
aws codebuild start-build --project-name image-build-stack-build-project --region ap-northeast-1 && BUILD_ID="image-build-stack-build-project:e8aeb764-5c76-480c-87e5-3a1183944c69" && while true; do STATUS=$(aws codebuild batch-get-builds --ids "$BUILD_ID" --region ap-northeast-1 --query 'builds[0].buildStatus' --output text); echo "Build status: $STATUS"; if [ "$STATUS" != "IN_PROGRESS" ]; then break; fi; sleep 10; done && echo "Final status: $STATUS"
```

## ECRのイメージを使ってデプロイ

では、ECRにプッシュされたコンテナイメージを使ってECS Express Modeでデプロイを行います。
以下のコマンドでCloudFormationスタックをデプロイします。

```bash
aws cloudformation deploy --template-file EcsExpress.yml --stack-name ecs-express-stack --capabilities CAPABILITY_NAMED_IAM --region ap-northeast-1
```

## 検証して思ったこと

とても簡単にECSのデプロイができましたが、個人的にはいくつか気になる点がありましたのでまとめてみます。

- Default VPCを使用する点
- ALBとECSを分離した設計にできない点
- コンテナイメージのビルドを自分で用意する必要がある点
- 従来のECSと同じく、ランニングコストが常に発生する点

### Default VPCを使用する点について

Default VPCが存在しなかったため、今回はコマンドを使ってDefault VPCを作成しました。
Default VPCの中にあるサブネットの特徴としてはすべてがパブリックサブネットである点です。

ドキュメントには以下のように記載されています。

> デフォルトでは、デフォルトサブネットはパブリックサブネットに指定されています。

引用：[デフォルトサブネット - Amazon Virtual Private Cloud](https://docs.aws.amazon.com/ja_jp/vpc/latest/userguide/default-subnet.html)

ECS Express ModeではDefault VPCを使用するため、タスク1つずつにパブリックIPアドレスが割り当てられてしまいます。
よって、セキュリティ面を考慮して実際に使うときはNetworkConfigurationを考慮する必要があります。

### ALBとECSを分離した設計にできない点

デプロイ時にALBとセットでデプロイされるため、分離した設計にできない点は厳しいところです。
Well-Architectに設計する場合は弾力性のあるロードバランサーをパブリックサブネットに配置し、同一ネットワークのプライベートサブネットにコンピューティングリソースを配置することが良いとされています。
（あるいはルーティングがセットされている別のプライベートネットワーク）
NetworkConfigrationでプライベートサブネットを指定することは可能ですが、ALBもまとめてプライベートになってしまうため、インターネットに公開することはできません。

### コンテナイメージのビルドを自分で用意する必要がある点

ECS Express Modeではコンテナイメージのビルドは自分で用意する必要があります。これは通常のECSと同じです。
このコンテナイメージをどのようにビルドしてECRに置いておくかが重要になります。今回はCodeBuildを使ってビルドしましたが、他にもGitHub Actionsなどを使うこともできます。最近のAWSではGitHub Actionsとの連携機能やGitLabとの連携機能も充実してきていますので、CI/CDパイプラインの一部として組み込むことができます。

### 従来のECSと同じく、ランニングコストが常に発生する点

ECS Express Modeは従来のECSと同じく、サービスが稼働している限りランニングコストが発生します。
例えば、1つのタスクが常に稼働している場合、その分のリソース使用料が発生します。
ECS Express Modeはデプロイの簡素化に焦点を当てていますが、コスト面では従来のECSと同様に考慮が必要です。

## ECS Express Modeを自動化する

AWSの公式ブログでは各種IaC(TerraformやAWS CDK、CloudFormation)にも対応していることが紹介されています。今回の検証ではCloudFormationテンプレートを使用してECS Express Modeの構築を自動化しましたので、IaCで自動化したい場合は以下の参考リンクを参照してください。

[AWS::ECS::ExpressGatewayService - AWS CloudFormation](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-ecs-expressgatewayservice.html)

### 余談：CloudFormationでECS Express Modeのネットワークを変更する場合

`AWS::ECS::ExpressGatewayService ExpressGatewayServiceNetworkConfiguration` プロパティを使用して、ECS Express Modeのネットワーク設定をカスタマイズできます。

## IAMロールに関すること

TaskExecutionRoleのポリシーでは`arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy`が必要であり、InfrastructureRoleには`arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices`が必要です。

これもまた不思議なところで、ECSといったらTaskExecutionRoleと`TaskRole`の2つが必要です。

ECS Express Modeを使う場合はTaskExecutionRoleとInfrastructureRoleの2つが必要になります。TaskRoleを明示的に指定しなくても良いということです。

※TaskRoleはAdditional Configuration(追加設定)で任意に指定できます。

## capacityProviderについて

ECS Express ModeではcapacityProviderの指定がありません。LaunchTypeとしてはFagateが使用されます。

## 削除する方法

ECSサービスを削除すると関連のリソースも削除されますが、クラスターは残るため手動で削除する必要があります。
ECSの起動に使ったリソースを全て削除する場合はDefault VPCとECRのリポジトリも手動で削除する必要がありますが、Default VPCは他のサービスで使用されている可能性があるため、注意が必要です。

## まとめ

ECS Express Modeを使ってみての感想としては、簡単にECSのデプロイが可能である点は魅力的でした。
アプリケーションをサクッとデプロイしてPoCしたい場合や、小規模なプロジェクトでECSを使いたい場合には特に有用だと感じました。

個人的にはALBを使わないECSの利用が多いのでそういう設定ができたらもっと便利になるのではないかと思いました。

# ここから下はログイン手順

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
