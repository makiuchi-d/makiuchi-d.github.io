---
layout: post
title: "GitHub Actionsをローカル環境で実行する「act」(KLabTechBook Vol.12)"
---

この記事は2023年11月11日から開催された[技術書典15](https://techbookfest.org/event/tbf15)にて頒布した「[KLabTechBook Vol.12](https://techbookfest.org/product/d20GG5Femwp1rTWSveSiHF)」に掲載したものです。

現在開催中の[技術書典17](https://techbookfest.org/event/tbf17)オンラインマーケットにて新刊「[KLabTechBook Vol.14](https://techbookfest.org/product/bZpYWjnBQDRe15rq1JdqqU)」を頒布（電子版無料、紙+電子 500円）しています。
また、既刊も在庫があるものは物理本を[オンラインマーケット](https://techbookfest.org/organization/5654456649646080)で頒布しているほか、
[KLabのブログ](https://www.klab.com/jp/blog/tech/2024/tbf17.html)からもすべての既刊のPDFを無料DLできます。
合わせてごらんください。

[<img src="/images/2024-11-03/ktbv14.jpg" width="40%" alt="KLabTechBook Vol.14" />](https://techbookfest.org/product/bZpYWjnBQDRe15rq1JdqqU)

--------

## GitHub Actions と act

GitHub ActionsはGitHubに統合されたCI/CDプラットフォームです。
リポジトリへのPushやPull Requestなどのイベントと関連付けて、自動テストやビルド、デプロイといったさまざまなワークフローを自動実行できます。

しかし、GitHub Actionsのワークフローを起動するには、コードをコミットしてリポジトリにPushしなければなりません。
このため、新しいワークフローを作成するときなど、動作確認のために毎回Pushする必要があり煩雑です。
また、単純なエラー、例えばタイポやコーディングスタイルのミスなどは、リポジトリにPushする前に検出したいところです。

そこで登場するのが「[act](https://github.com/nektos/act)」というツールです。
actを使えばGitHub Actionsのワークフローの各ジョブをローカル環境で実行でき、
リポジトリへコミットやPushをすることなく、事前にエラー検知できるようになります。
これにより、大人数での開発プロジェクトで起こりがちなジョブのランナーの枯渇も軽減できるでしょう。

この章では、GitHub Actionsをローカル環境で実行する「act」について、
基本的な使い方と制限事項、便利に使うためのTipsを紹介します。

## actのインストール

### Dockerの用意

actはGitHub ActionsのジョブのランナーをDockerコンテナによって再現するため、事前にDockerをインストールしておく必要があります。
Docker Desktop、またはその他のDocker環境をセットアップしてください。

### actのインストール

actのインストールはパッケージマネージャを使うと簡単です。
macOSやLinuxでよく使われているHomebrew、WindowsのChocolateyやWingetの他、
多くのパッケージマネージャに登録されています[^1]。
ご自身の環境にあわせて選ぶとよいでしょう。
リスト1とリスト2にHomebrewとChocolateyの例を示します。

[^1]: Homebrew、MacPorts、Chocolatey、Scoop、Winget、AUR、COPR、Nix など

▼リスト1 Homebrewによるインストール（Linux、macOS）
```shell
brew install act
```

▼リスト2 Chocolateyによるインストール（Windows）
```shell
choco install act-cli
```

また、actはGo言語で実装されているため、Goの開発環境が整っている場合はリスト3のようにインストールすることもできます。

▼リスト3 Goによるインストール
```shell
go install github.com/nektos/act@latest
```

### コンテナイメージの準備

actがインストールできたのでさっそく動かしたいところですが、その前に使用するコンテナイメージを準備しましょう。
actによって自動生成される設定では若干不都合があるので、リスト4のように設定ファイル`.actrc`を用意します[^2]。

▼リスト4 `.actrc`
```
-P ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-latest
-P ubuntu-22.04=ghcr.io/catthehacker/ubuntu:act-22.04
-P ubuntu-20.04=ghcr.io/catthehacker/ubuntu:act-20.04
```

[^2]: LinuxやmacOSでは`$HOME`（つまり`/home/ユーザ名/`）、Windowsでは`%USERPROFILE%`（つまり`C:\USER\ユーザ名\`）に配置します

このファイルはact実行時に毎回指定するコマンドラインオプションを記載するもので、
`-P` (`--platform`)オプションでジョブを実行するコンテナのイメージを指定しています。

また、actの実行によってコンテナイメージをダウンロードした場合、その進捗が表示されません。
あらかじめ`docker`コマンドでダウンロードしておく方が安心できます。

▼リスト5 dockerコマンドでのイメージのダウンロード
```shell
docker pull ghcr.io/catthehacker/ubuntu:act-latest
docker pull ghcr.io/catthehacker/ubuntu:act-22.04
docker pull ghcr.io/catthehacker/ubuntu:act-20.04
```

## actの実行

### ジョブの一覧

それでは、actを使ってみましょう。
最初にジョブ一覧を表示する`-l` (`--list`)オプションを紹介します。
リポジトリのルートディレクトリで`act -l`としてみます。

![ジョブ一覧](/images/2024-11-03/act-list.png)
▲図1 `ジョブ一覧`

これはKLabのOSS、[WSNet2](https://github.com/KLab/wsnet2)のジョブ一覧です。
リポジトリの`.github/workflow`以下のyamlファイルを読み取り、一覧化してくれます。

actでジョブを実行するときは、ここに表示されているJob IDやWorkflow file、Eventsの値を指定することになるので、
このコマンドで確認するとよいでしょう。

### ジョブの実行

`act`をパラメータなしで実行すると、すべてのジョブが実行されます。
しかし、これではログが見にくいことに加え、ローカルでの確認ではGitHubのイベントやJob IDを指定して必要なジョブだけ実行したいケースが多いでしょう。

たとえば、WSNet2で.NETアプリのビルドとテストを行う`dotnet`ジョブを実行するにはリスト6のようにします。

▼リスト6 actでdotnetジョブを実行
```shell
act pull_request -j dotnet -W .github/workflow/wsnet2-dotnet.yml
```

パラメータの`pull_request`でイベントを指定し、`-j` (`--job`)オプションでジョブを指定しています。
この場合`dotnet`ジョブを起動するイベントは`pull_request`しか定義されていないため、イベントの指定は省略できます。
また、`-W` (`--workflows`)オプションは複数のyamlファイルでワークフローを定義しているときに、どのyamlファイルのジョブかを識別するために必要になります。
WSNet2では`wsnet2-dotnet.yml`の他に`wsnet2-dashboard.yml`、`wsnet2-server.yml`が存在するため指定が必要です。

ここで、`dotnet`ジョブの中身をリスト7に示します。

▼リスト7 `wsnet2-dotnet.yml`
```yaml
name: WSNet2 dotnet ci

on:
  pull_request:
    branches: [ main ]
    paths:
      - '.github/workflows/wsnet2-dotnet.yml'
      - 'wsnet2-dotnet/**'
      - 'wsnet2-unity/**'

jobs:
  dotnet:
    runs-on: "ubuntu-latest"
    defaults:
      run:
        working-directory: wsnet2-dotnet
    steps:
      - uses: actions/checkout@v3
      - name: Setup .NET
        uses: actions/setup-dotnet@v3
        with:
          dotnet-version: "6.x"
      - name: dotnet build
        run:  dotnet build WSNet2.sln
      - name: dotnet test
        run:  dotnet test WSNet2.sln
```

まず注目していただきたいのが13行目の`runs-on: "ubuntu-latest"`です。
この行でジョブのランナーを指定しています。

ここで、`.actrc`に記載した`-P ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-latest`を思い出してください。
この`-P`オプションが、`runs-on`に指定された`ubuntu-latest`でのジョブの実行に使うコンテナイメージの指定になっています。

こうして指定されたイメージのコンテナを起動したら、actはyamlの17行目以降に指定された各ステップを順に実行していきます。

![ジョブの実行](/images/2024-11-03/act-run-dotnet-1.png)
▲図2 ジョブの実行

actは基本的には`steps`に定義されたアクションやコマンドをそのまま実行しますが、`actions/checkout`だけは例外です。
デフォルトではローカルのファイルを`docker cp`でコンテナ内に転送します[^3]。
これによりローカルの変更をリポジトリにコミットやPushしなくても、そのまま実行されるジョブの対象とできるわけです。

[^3]: `-b` (`--bind`)オプションを指定すると、バインドマウントによってファイルを同期するようにできます。

![ジョブの完了](/images/2024-11-03/act-run-dotnet-2.png)
▲図3 ジョブの完了

ジョブが完了すると、`Job succeeded`のログが表示されてコンテナも終了します。
エラーが発生したときはコンテナが消えずに残るため、アタッチして原因を究明できます。
もしエラー時にもコンテナを削除したい場合は`--rm`オプションを指定してください。

このほか詳しい使い方は[ユーザーガイド](https://nektosact.com/)をご覧ください。

## actの制限

ここまで紹介したように、actはDockerコンテナによってジョブの実行環境を再現します。
GitHubがホストするランナーはUbuntuだけでなくWindowsやmacOSも提供されていますが、
Dockerコンテナは基本的にはLinuxであるため、actではUbuntuのみをサポートします[^4]。
加えて、GitHubが提供するランナーと完全に同じ環境ではないため、動かないアクションもあるかもしれません。

[^4]: 筆者は試していませんが、実行環境が整っていればWindowsコンテナを使用してWindowsランナーを再現できるかもしれません。

また、サービスコンテナやジョブのタイムアウトなどいくつか[未実装の機能](https://nektosact.com/not_supported.html)があります。

サービスコンテナについては、手動でコンテナを起動することで一応対処できます。
ジョブ実行コンテナのネットワークモードはhostになっているため、
サービスコンテナ起動時に`-p` (`--publish`)オプションでポートをホストに公開しておくことで、
ジョブ実行コンテナからも`localhost`の該当ポートでサービスコンテナにアクセスできます。

## その他のTips

ここで、actで使える便利なTipsをいくつか紹介します。

### シークレットの受け渡し

GitHub上で保存したシークレットの値や`GITHUB_TOKEN`は、当然ながらactからは参照できません。
これらの値を必要とするジョブを実行するには、`-s` (`--secret`}または`--secret-file`オプションによって値を受け渡します。

このとき、コマンドラインで`act -s MY_SECRET=value`のように値を指定してしまうと、
コマンド履歴ファイルなどにシークレットの値が保存されてしまう可能性があり好ましくありません。
代わりに`act -s MY_SECRET`のようにして、コマンドラインでは値を指定せずにセキュアな対話インターフェイスで値を入力する方法が推奨されています[^5]。

[^5]: このとき環境変数@<tt>{MY_SECRET}が定義されているとそちらが優先されることに注意が必要です。

### actでの実行ではスキップする

actで実行しているときは特定のジョブやステップをスキップしたいこともあるでしょう。
actはジョブを実行するときに環境変数`ACT=true`を設定します。
これを利用して、リスト8のようにジョブやステップに[`if`条件文](https://docs.github.com/ja/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idif)を書くことでスキップできます。

▼リスト8 actでの実行時はスキップする
```yaml
jobs:
  my-job:
    runs-on: ubuntu-latest
    steps:
      - run: echo "スキップされない"

      - if: ${%raw%}{{ !env.ACT }}{%endraw%}
        run: echo "スキップされる"

      - run: echo "スキップされない"
```

### セルフホステッドランナーへの対応

GitHub Actionsでは、自身で用意したマシンでジョブを実行するセルフホステッドランナーもサポートされています。
セルフホステッドランナーでジョブを実行するには、`runs-on`に`self-hosted`を指定します。

actでセルフホステッドランナーに対応するには、まずランナーとなるコンテナイメージを用意します。
そのうえで、act実行時に`-P self-hosted=イメージ名` のようにコンテナイメージを指定します。
このとき、actは指定のイメージの最新版がないかオンラインのコンテナリポジトリを確認するのですが、
リポジトリ上にイメージが存在しない場合はエラーになってしまいます。
ローカルにしかないイメージを使うときは`--pull=false`オプションを指定して、最新版の確認をスキップする必要があります。

### `docker`コマンド使用時の注意点

actで実行されるコンテナ内でも`docker`コマンドを使用できます。
ただし、接続するDockerデーモンはコンテナ内ではなくactを実行しているホストで動いているものです[^6]。
このため、ポートなどのリソースの競合やバインドマウントするときのパスなどに注意する必要があります。

[^6]: ホストの`/var/run/docker.sock`がコンテナにバインドマウントされています。

### Dockerでuserns-remapを有効にしている場合

前巻 KLabTechBook Vol.11 第1章「[Dockerを使うなら当然userns-remapしてるよね！]({% post_url 2024-06-08-klabtechbook11-docker-userns-remap %})」で紹介したように、
LinuxでDockerを利用するときは`userns-remap`を有効にして一般ユーザーの名前空間でコンテナを動かすことをお勧めしています。

一方、actはコンテナをホストの名前空間で実行することを要求するので、コンテナ起動時に`--userns=host`オプションを指定する必要があります。
actでのジョブ実行時のオプションに`--container-options --userns=host`を追加することでこれを実現できます。
この設定を`.actrc`ファイルに記載しておくとよいでしょう。

## おわりに

この章では、GitHub Actionsをローカル環境で実行する「act」というツールについて、基本的な使い方を紹介しました。

GitHub Actionsはそれ自体でも十分すぎるほど強力なツールですが、
actを活用することでより効率的に使用できるでしょう。
ぜひ活用してみてください。

---

### コラム: デフォルトのコンテナイメージ

コンテナイメージを何も指定せずにジョブを実行しようとすると、
図4のようにデフォルトのコンテナイメージを選択する画面が表示されます。

![デフォルトイメージの選択画面](/images/2024-11-03/act-select-image.png)
▲図4 デフォルトイメージの選択画面

act version 0.2.52において、この表示内容は古く、実際のイメージと乖離しています。

<dl>
  <dt><strong>Large</strong></dt>
  <dd>
    利用されうるほぼすべてのツールがインストールされていますが、サイズは20GBどころか50GB以上あります。
    また現在はUbuntu 20.04と22.04がサポートされています。
  </dd>
  <dt><strong>Medium</strong></dt>
  <dd>
    アクションの起動に必要なツールのみインストールしてサイズは1.5GB以下に抑えられています。ほとんどのアクションが動作します。
  </dd>
  <dt><strong>Micro</strong></dt>
  <dd>
    表示のとおり、アクションを起動するためのNode.jsだけのイメージです。サイズも200MB未満です。
  </dd>
</dl>

これらのイメージはDocker Hubにホストされています。

|--|--|
|Large | `catthehacker/ubuntu:full-latest` など |
|Medium | `catthehacker/ubuntu:act-latest` など |
|Micro | `node:16-buster-slim` など |

actはジョブ実行時に最新のイメージがあるかを確認して自動的にpullするのですが、
このとき[Docker Hubのダウンロード率制限](https://matsuand.github.io/docs.docker.jp.onthefly/docker-hub/download-rate-limit/)に引っかかることがあります。
`catthehacker/ubuntu`のイメージと同じものがGitHubコンテナレジストリにも登録されているので、
`ghcr.io/catthehacker/ubuntu`のイメージを指定することで、この制限を回避できます。

---
