---
layout: post
title: "Makefileに秘められた真の力を開放する (KLabTechBook Vol.8)"
---

この記事は2021年7月10日から開催された[技術書典11](https://techbookfest.org/event/tbf11)にて頒布した「KLabTechBook Vol.8」に掲載したものです。

現在開催中の[技術書典16](https://techbookfest.org/event/tbf16)オンラインマーケットにて新刊「[KLabTechBook Vol.13](https://techbookfest.org/product/3CTYX4wj9wwBr13qJRYwA5)」を頒布（電子版無料、紙+電子 500円）しています。
また、既刊も在庫があるものは物理本を[オンラインマーケット](https://techbookfest.org/organization/5654456649646080)で頒布しているほか、
[KLabのブログ](https://www.klab.com/jp/blog/tech/2024/tbf16.html)からもすべての既刊のPDFを無料DLできます。
合わせてごらんください。

[<img src="/images/2024-05-29/ktbv13.jpg" width="40%" alt="KLabTechBook Vol.13" />](https://techbookfest.org/product/3CTYX4wj9wwBr13qJRYwA5)

--------

<p style="background-color:lightcyan;border-left:0.3em solid cyan;padding:0.5em">
<strong>ℹ️</strong>
この記事は以前投稿した「<a href="{% post_url 2022-01-27-make-go-generate %}">Makefileで必要なファイルだけgo generateするレシピ</a>」の詳細解説にもなっています。
</p>

皆さんはMakefileや`make`コマンドをどれだけ活用しているでしょうか。
OSSをビルドするときに`configure`やCMakeでMakefileを生成し、`make`コマンドを叩いたことのある人は多いでしょう。
そのほか、とある界隈では簡単なMakefileを記述して`make`をコマンドランチャーとして使うのが流行ったこともありました。
しかし、それだけでは`make`とMakefileが本来もつ力をちっとも活かせていません。

`make`の本来の機能は、Makefileへ記述された依存関係にしたがって、再生成が必要なファイルだけを効率よく生成してくれるものです。
この生成というのはソースコードのコンパイルに限りません。
Makefileを工夫して書くことで、多数のファイルを順に変換するような作業を格段に効率化できます。

本章では、複雑な依存関係を記述できる、Makefileの強力な機能を紹介します。
なお、ここで扱う`make`はGNU Makeとし、バージョン4.2.1で動作確認しています。

## Makefileの基本

Makefileにはファイル生成の**ルール**をリスト1のように記述していきます。

▼リスト1 Makefileのファイル生成ルール
```makefile
ターゲット: ソース1 ソース2
	生成コマンド1
	生成コマンド2
```

**ターゲット**（生成されるファイル）を行頭に書き、「`:`」を挟んだうしろに**ソース**（元となるファイル）を列挙します。
そして次の行からタブ字下げして**生成コマンド**を書いていきます。
この字下げは必ずハードタブでなければなりません。

ターゲットを生成するには「`make ターゲット`」のように実行します。
ターゲットの指定を省略すると、Makefileの中で最初に定義されたターゲットを指定したことになります。
このとき、ターゲットのタイムスタンプよりもソースのいずれかが新しいときに、生成コマンドが実行されます。

さらにこのルールは多段にもできます。

▼リスト2 多段ルールのMakefile
```makefile
ターゲット: 中間物1 中間物2
	ターゲット生成コマンド

中間物1: ソース1
	中間1生成コマンド

中間物2: ソース2
	中間2生成コマンド
```

リスト2のようなMakefileで`make`を実行すると、
`make`は「ターゲット」の元となる「中間物1」「中間物2」のファイルとルールを探します。
このとき「ソース2」だけが更新されていた場合「中間2生成コマンド」を実行して「中間物2」を更新しますが、
`make`は賢いので「中間物1」が「ソース1」より新しいのであれば中間1生成コマンドは実行しません。
そして「中間物2」が「ターゲット」より新しくなるので、「ターゲット生成コマンド」が実行されます。

このように、ルールを丁寧に記述しておけば、最小限のコマンド実行で最新の「ターゲット」を生成できるようになります。

## ファイル名のパターンを使ったルール

すべてのファイルについてルールを記述するのは大変ですが、
ターゲットのファイル名から単純にソースのファイル名が決まるような、たとえば拡張子が変わるだけの場合などでは、
「`%`」をワイルドカードとしたパターンルールが使えます。

▼リスト3 パターンルールの例]
```makefile
%.pb.go: %.proto
	protoc --go_out=. $<
```

リスト3はProtocol Buffersの`*.proto`ファイルからGo言語のコード`*.pb.go`を生成するパターンルールです。
「`make user.pb.go`」のようにターゲットを指定すると、「`user.proto`」をソースとしてターゲットを生成するルールとして働きます。
コマンドの中でターゲットやソースのファイル名を使うには「`$@`」や「`$<`」のような自動変数を利用します。

▼表1 主な自動変数

`$@`|ターゲット名
`$<`|ソースの先頭のもの
`$^`|すべてのソース
`$?`|ソースのうちターゲットより新しいもの
`$*`|`%`に一致した部分文字列

## ファイルの内容からルールを生成する

これまで紹介したように、Makefileではソースのファイル名と生成されるファイル名によってルールを記述します。
ここではさらに発展した例として、ファイルの内容からルールを生成する方法を紹介します。
まずはリスト4をご覧ください。

▼リスト4 ファイルの内容からルールを生成
```makefile
STRINGERS := $(shell grep -r '^//go:generate stringer ' . | \
        sed -E 's/^([^:]*):.*-type=([^ ]*)( .*)?$$/\1>\2/g')

define stringer_rule
$(eval params := $(subst '<', ,$1))
$(eval source := $(word 1,$(params)))
$(eval name := $(shell echo $(word 2,$(params)) | tr A-Z a-z)_string.go)
$(eval target := $(dir $(source)))$(name)
$(target): $(source)
	go generate $(source)
endef

$(foreach s,$(STRINGERS),$(eval $(call stringer_rule,$(s))))
```

これはGo言語の`stringer`というコード生成ユーティリティのためのルールを動的に生成するMakefileです。
`stringer`を利用するにはGoのソースコードにリスト5のようなコメントを書いておき、
`go generate`コマンドを呼び出すことでコードが生成されます。

▼リスト5 go generateのstringerの書式の例
```go
//go:generate stringer -type=MyEnum
```

ここでは`stringer`の詳細は省きますが、このコメントの書かれたファイルがソースになります。
そして出力されるファイル名は、`-type`で指定された型名を小文字にして`_string.go`を付けたもの、
この例の場合は`myenum_string.go`になります。
つまり、リスト5の書かれたファイルを検索し、
書かれている型名から生成されるファイル名を構築すればルールを生成できます。
そしてそのルールを`make`に認識させれば、必要なときだけコマンドを実行する効率のよいMakefileとなります。
それでは順番に見ていきましょう。

### ソースの検索と型名の抽出

▼リスト6 ソースの検索と型名の抽出
```makefile
STRINGERS := $(shell grep -r '^//go:generate stringer ' . | \
        sed -E 's/^([^:]*):.*-type=([^ ]*)( .*)?$$/\1>\2/g')
```

Makefileにはさまざまな関数が用意されていて、`$(function param,param,...)`の形で呼び出せます。
ここで使っているのは`shell`関数です。
その名から分かるとおりシェルコマンドを呼び出し、標準出力の文字列に展開されます。

ここではまず`grep`で「`//go:generate stringer `」を含むファイル名とその行を抽出しています。
つづいてパイプで`sed`に流し込み、`ファイル名>型名`の形に編集しています。
たとえばリスト5の書かれたファイル`myprogram.go`がある場合、「`./myprogram.go>MyEnum`」のようになります。
ファイルが複数ある場合コマンドの出力は複数行になりますが、`shell`関数はそれを空白文字区切りのリストとして展開します。
こうして得られたリストを`STRINGERS`変数に格納しています。
この変数はあとで`$(STRINGERS)`と書くことで展開できます。

### ルールのテンプレート

続いて、`define`〜`endef`の部分です。
Makefileでは変数への値の格納は`:=`などによる代入が一般的ですが、
GNU Makeでは`define`を使うことで、複数行にまたがるような文字列も変数へ格納できます。

▼リスト7 テンプレートの定義
```makefile
define stringer_rule
$(eval params := $(subst '<', ,$1))
$(eval source := $(word 1,$(params)))
$(eval name := $(shell echo $(word 2,$(params)) | tr A-Z a-z)_string.go)
$(eval target := $(dir $(source))$(name))
$(target): $(source)
	go generate $(source)
endef
```

リスト7では「`stringer_rule`」という名前でテンプレートとして使用する変数を定義しています。
この変数はあとで`call`関数で呼び出します。

▼リスト8 call関数
```makefile
$(call variable,param,param,…)
```

`call`関数は、変数`variable`にパラメータを与えて展開します。
各パラメータには`$1`、`$2`……の形でアクセスできます。

`stringer_rule`のパラメータには、さきほど`STRINGERS`変数に格納した「`./myprogram.go>MyEnum`」を渡します。
まずは`subst`関数でパラメータ`$1`の`>`を空白に置換し、リストの形にして`params`に保存します。
ここで、`call`関数によるテンプレートの展開の時点では、`:=`を含む文字列を生成するだけで代入は行われません。
このため、`eval`関数で評価することで変数への代入を実行します。

`params`をリストにしたことで、`word`関数でファイル名と型名を取り出せます。
1番目がファイル名「`./myprogram.go`」、2番目が型名「`MyEnum`」となっています。
ソースとなるファイル名はこれで取り出せます。

続いて、リスト9ではターゲットとなるファイル名を型名から生成します。

▼リスト9 ターゲットファイル名の生成
```makefile
$(eval name := $(shell echo $(word 2,$(params)) | tr A-Z a-z)_string.go)
```

Make自体に小文字へ変換する関数がみあたらないので、`shell`関数で`tr`コマンドを呼び出すことにし、
後ろに「`_string.go`」を結合して`name`変数に格納しています。
実は、LinuxなどGNUの`sed`であれば型名を抽出する段階で`\L`で小文字変換できるのですが、
macOSの`sed`にはそのような機能がないので、ここでは`tr`コマンドを利用しています。

`stringer`ではソースと同じディレクトリにファイルを生成するので、
`dir`関数を使ってソースのディレクトリ名を取り出しファイル名と結合してターゲット名とします。

ここまでの処理をまとめると、パラメータとして「`./myprogram.go>MyEnum`」が渡された時、
テンプレート`stringer_rule`はおよそリスト10ように展開されます。

▼リスト10 展開されたテンプレート
```makefile
params := ./myprogram.go MyEnum
source := ./myprogram.go
name := myenum_string.go
target := ./myenum_string.go
./myenum_string.go: ./myprogram.go
	go generate ./myprogram.go
```

### すべての対象でテンプレート展開

リスト11 すべての対象にテンプレートを適用
```makefile
$(foreach s,$(STRINGERS),$(eval $(call stringer_rule,$(s))))
```

最後にリスト11の行では、最初に検索した`STRINGERS`の各要素に対して、
`call`関数と`eval`関数を呼び出しています。

▼リスト12 foreach関数
```makefile
$(foreach var,list,text)
```

`foreach`関数は、`list`に与えられた空白文字区切りのリストのそれぞれの要素ついて、`text`を適用していきます。
`text`の中では処理中の要素は`var`の名前でアクセスできます。

最初に検索した`STRINGERS`は「`./dir1/program1.go>Enum1 ./dir2/program2.go>Enum2`」のような空白文字区切りのリストになっています。
これが`foreach`によって、リスト13のように適用されることになります。

▼リスト13 foreachの適用イメージ
```makefile
$(eval $(call stringer_rule,./dir1/program1.go>Enum1))
$(eval $(call stringer_rule,./dir2/program2.go>Enum2))
```

そして`call`関数によってテンプレートが展開されるとリスト14になります。

▼リスト14 callによる展開イメージ
```makefile
$(eval
./dir1/enum1_string.go: ./dir1/program1.go
	go generate ./dir1/program1.go
)
$(eval
./dir2/enum2_string.go: ./dir2/program2.go
	go generate ./dir2/program2.go
)
```

`call`関数で展開されたものはまだただの文字列ですので、これを`eval`関数で評価することで、
`make`のルールとして認識されます。

このようにして、ファイル内の`stringer`の書式からルールを生成できました。
これで`make`実行時に効率よく必要なファイルだけ`go generate`を呼び出すようになりました。

## まとめ

Makefileにはこの他にも`ifeq`のような条件文やさまざまな関数、
`make`自体を再帰的に使う方法などたくさんの構文があり、
一記事ではとても紹介しきれないほど高機能です。
使いこなせばあらゆる状況で効率よくファイルを生成するルールを自在に記述できるでしょう。

しかし、なんでもMakefileでやってしまうのは可読性の面からもお勧めできません。
この記事で紹介した`stringer`のルール生成を初見で理解できる人はそういないと思います。

とはいえ、シンプルなルールを書くだけでも役に立つ場面はきっと多いことでしょう。
Makefileをうまく使って、日々の作業を効率化していきましょう。
