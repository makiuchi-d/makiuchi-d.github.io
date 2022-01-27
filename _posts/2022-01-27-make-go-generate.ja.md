---
layout: post
title: "Makefileで必要なファイルだけgo generateするレシピ"
---

Go言語にはコード生成をサポートする`go generate`コマンドがあり、活用している人も多いと思います。
ところが、コードベースが大きくなってくるとコード生成にかかる時間が気になってきますし、
コード生成に関係ないファイルを編集したときに再生成するのは単純に無駄です。

この問題をスマートに解決してくれるのがそう、`make`コマンドです。

`make`はMakefileに書かれた依存関係に従って、必要なコマンドだけを実行してくれます。
また並列実行もサポートしています。

ところで、Makefileは書くのが難しい（だからCMakeなどがある）と思っているかもしれませんがそれは間違いです。
難しいのはコンパイラの違いやライブラリの有無によって分岐することであって、
Goは基本的に全部入りなのでそんな面倒事は全くありません（cgoは一旦忘れましょう）。

## Makefileの基本

Makefileには生成されるファイルとそのソースとなるファイル、そしてそれを生成するコマンドを依存関係のルールとして書いていきます。
`make`はこのルールに従って、生成物よりソースのタイムスタンプが新しいときだけコマンドを実行していってくれます。
ルールが多段になっていても賢く解決してくれます。

```make
生成物: ソース1 ソース2
	コマンド1
	コマンド2
```

生成物とソースは`:`で区切り、続く行にコマンドを字下げして書いていきます。
コマンドの字下げはハードタブです。Goと一緒ですね！

生成物やソースのファイル名には`%`を使ったパターンでも書けます。

これだけでも十分便利なのですが、今回やりたい`go generate`はgoのファイル中に情報が書かれています。
それらをひとつひとつMakefileに書き出すのは面倒なので、ファイルの内容からルールを自動的に取り出せるともっと楽ですね。

## ファイルの内容からルールを生成する

例えば`stringer`の場合、次のようなコメントをコード中に書きます。

```go
//go:generate stringer -type=StatusCode
```

ソースとなるのはこれが書かれたファイル、出力されるのは小文字にした型名に接尾辞を付けて`statuscode_string.go`になります（オプションによる指定は一旦考えないことにします）。
まずはこの組を`grep`と`sed`コマンドで取り出し、Makefileの中でテンプレートを適用して動的にルールを生成します。

_※ここで使う`sed`はGNUの`sed`です。macOSの`sed`は`\L`が使えないので、coreutilsをインストールするか`tr`コマンドを組み合わせて頑張ってください。_

```gnumake
# go:generateの書式が書かれているファイルからソースと生成物のペアを抽出
go_gen_src := $(shell grep -r '^//go:generate stringer ' --include='*.go' . | \
                sed -E 's/^([^:]*\/)([^\/:]*):.*-type[= ](\w*).*$$/\1\2>\1\L\3_string.go/g')
# 生成物のリストを取り出す
go_gen_dst := $(foreach s,$(go_gen_src),$(word 2,$(subst >, ,$s)))

.PHONY: all

all: $(go_gen_dst)

# ルール生成のテンプレート
define go_generate_rule
$(eval src := $(word 1,$(1)))
$(eval dst := $(word 2,$(1)))
$(dst): $(src)
	go generate $(src)
endef

# テンプレートを使ってルールを動的生成
$(foreach s,$(go_gen_src),$(eval $(call go_generate_rule,$(subst >, ,$(s)))))
```

## パフォーマンス

このMakefileを使う場合も結局全てのファイルを捜査しますし少々複雑な正規表現も使っています。
これで`go generate`より遅くなっては元も子もありません。

そこで、Goのソースコードの中で`stringer`が使われているパッケージを適当に探して、実行時間を比べてみました。

```console
makki:~/Projects/go/src/cmd/compile/internal/ir[GIT]$ time go generate .

real    0m0.566s
user    0m0.953s
sys     0m0.345s

makki:~/Projects/go/src/cmd/compile/internal/ir[GIT]$ time make
make: 'all' に対して行うべき事はありません.

real    0m0.013s
user    0m0.014s
sys     0m0.003s
```

なにも変更していない場合、40倍以上Makefileを使うほうが早いですね。


## まとめ

makeで効率よくgo generateする方法を紹介しました。
`grep`と`sed`を工夫すれば、出力ファイル名をオプションで指定している場合や`stringer`以外のコマンドにも使える方法です。
みなさんも使ってみてください。

## 宣伝

もう少し詳しい説明や、macOSでも使えるMakefileの例を技術同人誌「KLab Tech Book Vol.8」に掲載しています。
また、現在開催中の技術書典12にて、新刊[「KLab Tech Book Vol.9」](https://techbookfest.org/product/6349425553178624?productVariantID=6307395993075712)を頒布しています。
物理本は1000円ですが、電子版は0円です。
既刊PDFも次のページから無料でダウンロードできますので、ぜひ読んでみてください。

[技術書典12で同人誌を頒布します & 既刊PDFダウンロードページ](https://www.klab.com/jp/blog/tech/2022/tbf12.html)
