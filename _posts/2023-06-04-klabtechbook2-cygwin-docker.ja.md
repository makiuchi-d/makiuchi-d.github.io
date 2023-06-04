---
layout: post
title: "Cygwin環境でDockerを快適に使うために"
---

この記事は2018年4月22日に[技術書典4](https://techbookfest.org/event/tbf04)にて頒布した「KLabTechBook Vol.2」に掲載したものです。
当時のまま転載しているので現在では適さない部分もあります。僕も今ならCygwinではなくWSLを選びますし。

現在開催中の[技術書典14](https://techbookfest.org/event/tbf14)にて新刊「[KLabTechBook Vol.11](https://techbookfest.org/product/m6LUwU6LgC1FbEW3NVhw14)」を頒布（電子版無料、紙+電子 500円）しています。
また、[KLabのブログ](https://www.klab.com/jp/blog/tech/2023/tbf14.html)からすべての既刊のPDFを無料DLできます。
合わせてごらんください。

[<img src="/images/2023-05-22/ktbv11.jpg" width="40%" alt="KLabTechBook Vol.11" />](https://techbookfest.org/product/m6LUwU6LgC1FbEW3NVhw14)

--------

## はじめに

Cygwinは、Unixライクな環境に慣れきっている人々がWindowsを利用するにあたって救いとなるソフトウェアなのは皆さんご存知のところと思います[^1]。
また、モダンな開発シーンではDockerを使うことも増えてきました。
しかし、Cygwin環境からDockerを使おうとすると後述するいくつかの問題にぶつかります。

この章では、どうしてもCygwinから離れられない筆者のような人が、Cygwin環境のままDockerを快適に使えるようにする方法についてまとめます。
また、試行錯誤の過程をQiitaに投稿してありますので、合わせてご覧ください[^2]。

[^1]: 現在ではCygwin以外にもMSYS2やWindows Subsystem for Linuxなど複数の選択肢があります。よい時代になりましたね。
[^2]: [Cygwin環境でdockerコマンドを使えるようにするまでの奮闘記](https://qiita.com/makiuchi-d/items/7f177cc90c75af40e5ad)

### 環境について

動作確認はWindows 7上のDocker Toolboxで行っています。
バージョンに制限は特に無いはずです。
Windows 10 ProとDocker for Windowsの組み合わせでは確認をしていませんが、動作原理的には同じように使えると思われます。

## CygwinでDockerを使うときの問題点

Docker ToolboxにはデフォルトのターミナルとしてDocker Quickstart Termnal（GitBash）が付属しています。
しかし普段Cygwinで生活しているのであれば、Cygwinの環境のまま`docker`コマンドを使いたくなってきます。

ドキュメント[^3]を参考に環境変数やパスの設定をすることでDocker Toolboxの`docker`コマンドを呼び出すことはできるようになります。
ただ、このままでは次の2つの問題点があり、実用できるとはとてもいえません。

[^3]: [Docker Machine コマンドラインリファレンス env](https://docs.docker.jp/machine/reference/env.html)

### TTYオプションが使えない

mintty（Cygwinの標準ターミナル）を使っている場合に`docker run`や`docker exec`で疑似TTYオプション（`--tty`あるいは`-t`）を指定したとき、TTYモードを有効にできないというエラーが発生します。

```term
$ docker run -it ubuntu
cannot enable tty mode on non tty input
```

これは他のターミナルエミュレータを使うことで回避することもできますが、minttyのままで回避する方法を「TTYモードを有効にできない問題を回避する」で解説します。

### そのままのパスをパラメータに指定できない

Cygwin環境は独自のルートディレクトリを持ち、さらにWindowsの各ドライブを/cygdrive以下に配置するという独特のディレクトリ構成になっています。
しかし`docker`コマンドはCygwinのアプリケーションでは無いため、Cygwin環境のファイルパスをそのまま`docker`のパラメータに指定しても、それは存在しないパスとして解釈されてしまいます。

この問題の回避方法について解説します。

## TTYモードを有効にできない問題を回避する

この問題は、minttyのサイトmintty[^4]にも書いてあるように、minttyの疑似TTYがWindowsのネイティブコンソールと互換を持たないためです。
Windowsのネイティブコンソールアプリケーションをminttyで動かすには、winptywinpty[^5]を使って疑似TTYとネイティブコンソールの橋渡しをする方法もありますが、ここでは筆者が最終的にたどり着いた`ssh`コマンドを利用する方法について解説します。

[^4]: [https://mintty.github.io/#compatibility](https://mintty.github.io/#compatibility)
[^5]: [https://github.com/rprichard/winpty](https://github.com/rprichard/winpty)

### SSHコマンドによるネイティブコンソールの回避

さて、DockerはLinuxカーネルの機能に依存しているため、Windows上で直接動作することはできません。
Docker ToolboxやDocker for WindowsではLinuxの仮想マシン（VM）を動かし、その中でDockerが立ち上がっています。
そしてVM内には`docker`コマンドも用意されており、VMにログインして`docker`コマンドを叩くことができます。

このVMでは`sshd`も立ち上がっているため、一般的なSSHクライアントで接続することができます。
そしてCygwinの`ssh`コマンドには`-t`（仮想TTY）オプションがあるため、これでminttyのTTYとVM内の`docker`コマンドのTTYを直接つなぐことができます。

つまり、`ssh`コマンドで直接VM内の`docker`コマンドを叩くことにより、Windowsネイティブの`docker.exe`を使う必要がなくなり、ネイティブコンソールを完全に回避できるのです[^6]。

[^6]: Linuxの仮想マシンが動いてさえいえれば、VirtualBoxだろうと他の仮想化技術だろうと使える方法です。Docker Toolboxとはなんだったのか。

### ラッパースクリプトによる実装例

SSHを使ってVM内の`docker`コマンドを叩くものを、ラッパースクリプトとして実装してみます。
このとき、`docker run`や`docker exec`で疑似TTYオプションが指定されている場合は、`ssh`にも`-t`オプションをつけて呼び出すようにします。

接続するVMのIPアドレスやユーザ名、使用する鍵といった情報は、`docker-machine inspect`コマンドで取得することができます。
ここに含まれるファイルパスはWindowsの形式になっているため、Cygwinのパスに忘れずに変換しておきましょう。

▼ SSHを使ってdockerコマンドを叩くbashスクリプト
```bash
#!/bin/bash -e

cmd=(docker "$@")
ttymode=false

# exec/run で -t/--tty があるときのみ ttymode=true
case "$1" in
    "exec" | "run")
        shift
        while [[ $# -gt 0 && $1 =~ ^- ]]; do
            if [[ "$1" =~ ^-[^-=]*t || "$1" =~ ^--tty(=true)? ]]; then
                ttymode=true
            fi
            if [[ "$1" =~ ^-[^-=]*t=false || "$1" == "--tty=false" ]]; then
                ttymode=false
            fi
            shift
        done
        ;;
esac

# SSH接続に必要な情報を集める
INSPECT=$(docker-machine inspect)
SSHUSER=$(echo "$INSPECT" | grep -Po '"SSHUser":\s*"\K[^"]*(?=",)')
SSHKEY=$(echo "$INSPECT" | grep -Po '"SSHKeyPath":\s*"\K[^"]*(?=",)' |\
    sed -E 's|^(\w+):|/cygdrive/\L\1|;s|\\\\|/|g')
VMADDR=$(echo "$INSPECT" | grep -Po '"IPAddress":\s*"\K[^"]*(?=",)')

# ttymode有効のときだけssh -tにする
sshopt=""
if $ttymode; then
    sshopt="-t"
fi

ssh $sshopt -q -i "$SSHKEY" "$SSHUSER"@"$VMADDR" "$(printf "%q " "${cmd[@]}")"
```

このスクリプトを`docker`という名前でPATHの通った場所においておけば、普段とまったく同じ感覚で`docker`コマンドを利用できるようになります。
`winpty`を使った場合と違い、標準入出力をパイプにしても問題なく動きます。

もしかしたら`docker-machine`コマンドの応答待ち時間が気になるかもしれません。
複数のVMを切り替えるようなことが無いのであれば、接続先情報を固定値にしてしまうことでさらに快適にすることもできます。
ぜひお試しください。


## Cygwin環境のパスをそのまま指定できるようにする

`docker run`時のボリュームのマウント（`--volume`または`-v`）などでWindows上のファイルやディレクトリを`docker`コマンドに渡すことはよくあります。
VM内で動作しているDockerは、ホストであるWindowsのファイルやディレクトリにどうやってアクセスしているのでしょうか。

答えは単純で、共有フォルダとしてVM内にマウントしているのです。Docker Toolboxの場合、初期設定でWindowsのC:\UsersをVM内の/c/Usersにマウントしています。
ということは、C:\Users以外の場所を渡すことは初期設定のままではできません。

一方、特にボリュームのマウントではフルパスでの指定を求められるのですが、これがVM内でのフルパスになっていないとDockerは解釈できません。

Cygwin環境でのフルパスは、C:\Usersは/cygdrive/c/Usersとなってしまい、VM内のフルパスとは異なります。
加えてCygwinの/home以下などのパスについても、/c/Users以下の対応するパスに書き換える必要があります。

ここでもまたラッパースクリプトで、`docker`コマンドに渡す前にパスを変換することで回避していきます。

### Cygwin環境のパスをVM内のパスに変換する

Cygwinに付属している`cygpath`コマンドで、Cygwin環境のパスをさまざまな形式のパスに変換することができます。
特に`cygpath -am`とすると、ドライブレターから始まる“/”区切りのフルパスが得られ、都合がよいです。

```cmd
$ file WinHome
WinHome: symbolic link to /cygdrive/c/Users/makiuchi-d

$ cygpath -am WinHome/Projects
C:/Users/makiuchi-d/Projects
```

このようにシンボリックリンクも解決してくれるので、先頭のドライブレター部分を小文字にして“/”で始まるように置換するだけで済みます。
これを`dmpath`という関数として定義したものを示します。

▼ cygwin環境のパスをVM内のパスに変換するコマンド
```
function dmpath ()
{
    cygpath -am "$1" | sed -E 's|^(\w*):|/\L\1|'
}
```

### パスが与えられるパラメータ部分だけパスを変換する

コマンドラインのパラメータを列挙しただけでは、どれが変換すべきパスなのか判別がつきません。
それどころか、`docker cp`では2つのパラメータのうち“:”の無い方だけをパス変換しなければならない一方で、
`docker run -v`の場合は“:”の前半のみパス変換しなければならなず、
さらに、コンテナ内で実行するコマンドのオプションについては変換してはならないなど、対応方法が千差万別です。

正しく動作させるためには、知りうる限りのオプションを片っ端からチェックしていく以外になさそうです。

ここでは`docker cp`と`docker run`の一部のオプションについてパス変換したものを示します。

▼ 適切なパラメータのパスを変換してdockerを呼び出すbashスクリプト
```
#!/bin/bash -e
# dmpath()の定義は省略

cmd=(docker "$@")

case "$1" in
    "cp")
        cmd=(docker cp)
        shift
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -* | *:*)  # オプションやコンテナ内のパスは変換しない
                    cmd=("${cmd[@]}" "$1")
                    ;;
                *) # それ以外は変換する
                    cmd=("${cmd[@]}" "$(dmpath "$1")")
                    ;;
            esac
            shift
        done
        ;;
    "run")
        cmd=(docker run)
        shift
        while [[ $# -gt 0 && $1 =~ ^- ]]; do
            # volumeオプションはホスト側のパス部分を取り出して置換
            if [[ "${1%=*}" =~ ^-[^-]*v$ || "${1%=*}" = "--volume" ]]; then
                case "$1" in
                    *=*)
                        opt="${1%=*}"
                        paths="${1#*=}"
                        ;;
                    *)
                        opt="$1"
                        paths="$2"
                        shift
                        ;;
                esac
                cmd=("${cmd[@]}" "$opt" "$(dmpath "${paths%:*}"):${paths#*:}")
            # 引数を取るオプションは次のパラメータも一緒に処理（一部）
            elif [[ "$1" =~ ^-[^-]*[aelpuw]$ ||
                    "$1" = "--attach" ||
                    "$1" = "--env" ||
                    "$1" = "--label" ||
                    "$1" = "--link" ||
                    "$1" = "--mount" ||
                    "$1" = "--name" ||
                    "$1" = "--publish" ||
                    "$1" = "--user" ||
                    "$1" = "--workdir" ]]; then
                cmd=("${cmd[@]}" "$1" "$2")
                shift
            # その他のパラメータはそのまま追加
            else
                cmd=("${cmd[@]}" "$1")
            fi
            shift
        done
        # パラメータ以外（image名以降）は置換せず追加
        cmd=("${cmd[@]}" "$@")
        ;;
esac

$(printf "%q " "${cmd[@]}")
```

このスクリプトでは、`docker run`のパラメータを網羅できていません。
たとえば、デタッチキーを変更する`--detach-keys`は追加のパラメータを要求しますが、このままでは単独で使われるパラメータとして判定されてしまい、キー文字列をイメージ名と判定してしまいます。

少なくとも自身で使うパラメータはすべて網羅しなければなりません。
もしエレガントな解決策などありましたらご教示ください。

また、ここに示した`docker cp`、`docker run`以外にもパスを受け取るコマンドがあります。
それらについても同様の方法でパス変換することで、この問題は解決できます。

このようなラッパースクリプトを用いることで、パス名に関してCygwin環境であることを意識することなく`docker`コマンドが使えるようになります。

## まとめ

Cygwin環境で`docker`コマンドを使うときにぶつかる、疑似TTYの問題とパス名の問題について回避策を示しました。

紙面と解説の都合上、それぞれの回避策を別々のスクリプトとして紹介しましたが、この2つの回避策を統合し、さらにコマンドパラメータをより多く網羅したものをGitHubにて公開しています[^7]。

これによりCygwin環境でも快適にDockerを利用できるようになりました。
お困りの方はぜひご利用ください。


最後に強く言いたいことは、Dockerを使うならホストもLinuxにしましょう。

[^7]: [https://github.com/makiuchi-d/docker-in-cygwin](https://github.com/makiuchi-d/docker-in-cygwin)
