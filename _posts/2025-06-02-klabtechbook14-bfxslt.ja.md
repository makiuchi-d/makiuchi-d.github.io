---
layout: post
title: "XMLプログラミング言語「XSLT」の可能性 (KLabTechBook Vol. 14)"
---

この記事は2024年11月2日から開催された[技術書典17](https://techbookfest.org/event/tbf17)にて頒布した「[KLabTechBook Vol. 14](https://techbookfest.org/product/bZpYWjnBQDRe15rq1JdqqU)」に掲載したものです。

現在開催中の[技術書典18](https://techbookfest.org/event/tbf18)オンラインマーケットにて新刊「[KLabTechBook Vol.15](https://techbookfest.org/product/xmtJPdPuamKDgrnmkek9pn)」および既刊を頒布（電子版無料、紙+電子 500円）しているほか、[KLabのブログ](https://www.klab.com/jp/blog/tech/2025/tbf18.html)からもすべての既刊のPDFを無料DLできます。

[<img src="/images/2025-06-02/ktbv15.png" width="40%" alt="KLabTechBook Vol.15" />](https://techbookfest.org/product/xmtJPdPuamKDgrnmkek9pn)

また、6月14日〜15日に開催される[関数型まつり2025](https://fortee.jp/2025fp-matsuri)に、
この記事の内容を元にしたセッション「[XSLTで作るBrainfuck処理系――XSLTは関数型言語たり得るか？](https://fortee.jp/2025fp-matsuri/proposal/8dcaecb5-4541-4262-a047-3e330a7bcdb8)」で登壇します。
参加される方はぜひ直接のツッコミをお願いします。

[<img src="/images/2025-06-02/fp-matsuri-xslt.png" alt="XSLTで作るBrainfuck処理系――XSLTは関数型言語たり得るか？" />](https://fortee.jp/2025fp-matsuri/proposal/8dcaecb5-4541-4262-a047-3e330a7bcdb8)

--------

## ことのはじまり

それは、とある勉強会の懇親会でのことでした。
出版業界の方とお話する中で、組版作業でXMLとXSLTを利用することがあると聞きました。
XSLTはXMLを整形するためのテンプレート言語で、それ自体もXMLで記述します。
さらに驚くべきことに、XSLTはテンプレート言語でありながらチューリング完全だといいます。
つまり、XSLTは**XMLのXMLによるXMLのためのプログラミング言語**なのです。

ところで筆者は以前KLabTechBook Vol.1にて、M4というマクロ言語がチューリング完全であることを示しました[^1]。
そうです、またなのです。確かめたくなってしまったのです。

[^1]: [テキストマクロプロセッサ「M4」のチューリング完全性について](/2023/05/22/klabtechbook1-bfm4.ja.html)

今回も同様に、XSLTでBrainfuckのインタプリタを実装することで、XSLTがチューリング完全であることを確認したいと思います。

## XSLTとは

XSLT（Extensible Stylesheet Language Transformations）は、主にXMLを整形・変換するためのテンプレート言語です。
XML文書を受け取り、それを他の形式（HTML、テキスト、あるいは別のXML）に変換することができます。

次の例はXSLTでXML文書を表示用HTMLに変換するものです。
リスト1は図書館の蔵書を表すXML文書です。
これにリスト2のように書かれたXSLテンプレートを適用することで、
表示用に整形されたリスト3のHTMLを出力しています。

▼リスト1 入力のXML文書
```xml
<?xml version="1.0" encoding="utf-8"?>
<library>
  <book>
    <title>Learning XSLT</title>
    <author>John Doe</author>
  </book>
  <book>
    <title>XML in Action</title>
    <author>Jane Smith</author>
  </book>
</library>
```

▼リスト2 XSLテンプレート
```xml
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html"/>
  <xsl:template match="/">
    <html>
      <body>
        <h1>Library Books</h1>
        <ul>
          <xsl:apply-templates select="library/book" />
        </ul>
      </body>
    </html>
  </xsl:template>
  <xsl:template match="book">
    <li>
      <strong>
        <xsl:value-of select="title"/>
      </strong> by <xsl:value-of select="author"/>
    </li>
  </xsl:template>
</xsl:stylesheet>
```

▼リスト3 出力HTML
```html
<html>
  <body>
    <h1>Library Books</h1>
    <ul>
      <li><strong>Learning XSLT</strong> by John Doe</li>
      <li><strong>XML in Action</strong> by Jane Smith</li>
    </ul>
  </body>
</html>
```

XSLTはテンプレートマッチングを駆使して文書の特定の部分に応じた処理を行います。
この例では、XSLの `<xsl:template match="/">` のテンプレートが文書全体にマッチして呼び出され、
その中の `<xsl:apply-templates select="library/book"/>` で、
孫要素の `<book>` それぞれに対してマッチするテンプレート `<xsl:template match="book">` が呼び出される形となっています。

XSLTには `xsl:if` や `xsl:for-each` のような制御構文もありますが、
このようなテンプレート言語が本当にプログラミング言語と言えるのでしょうか？

## チューリング完全性について

### チューリング完全とは

プログラミング言語であるためには、その言語がチューリング完全であることが必要だとよく言われます。

チューリング完全とは、チューリングマシンと同等の計算能力があることを意味します。
チューリングマシンはアラン・チューリングによって考案された仮想の機械で、無限に長いテープ（記憶装置）と、
そこに対してデータを読み書きするヘッドで構成されています。
この機械に、ヘッドの移動や読み書きを指示するプログラムを与えることで動作する計算機です。

![チューリングマシンの概念図](/images/2025-06-02/turing-machine.png)<br/>
▲図1 チューリングマシンの概念図

チューリングマシンは非常に単純な構造ですが、これまでに知られているどんな複雑な計算機械でも、
理論上チューリングマシンで再現できることが知られています。
そして計算可能なあらゆるアルゴリズムは、このチューリングマシンでも計算できるとされています[^2]。

[^2]: 原義的には、計算可能性を定義するためにチューリングマシンが利用されています。

プログラミング言語であるならば、あらゆる計算問題に対応できなくてはなりません。
チューリング完全であれば、どんな計算問題でも計算できることが理論的に保証されるわけです。
これが、プログラミング言語がチューリング完全であることを必要とする理由です。

### Brainfuckとチューリング完全

ある言語がチューリング完全であることを示す方法のひとつが、すでにチューリング完全であることがわかっている言語の処理系をその言語で実装することです。
チューリング完全な言語で書かれたプログラムをすべて実行できるのであれば、その言語を通せばあらゆる計算を実行できることになり、
チューリング完全であると言えるわけです。

ところで、Brainfuckというプログラミング言語をご存知でしょうか？
この言語は記号のみで記述する、いわゆる難解プログラミング言語のひとつとして知られていますが、
実は非常に有用な特徴を持っています。

▼リスト4 Brainfuckで`Hello, world!`
```brainfuck
+++++++++[>++++++++>+++++++++++>+++++<<<-]>.>++.+++++++..+++.>-.
------------.<++++++++.--------.+++.------.--------.>+.
```

Brainfuckの処理系は、1次元のメモリ配列とそのアドレスを示すポインタを1つ持ち、
プログラムはポインタの移動とメモリ上の値の読み書きといった命令の列になっています。

![Brainfuck処理系の概念図](/images/2025-06-02/brainfuck.png)<br/>
▲図2 Brainfuck処理系の概念図

ご覧のとおり、Brainfuckの処理系はチューリングマシンとほぼ同一の構成になっていて、チューリング完全であることが自明です。
加えて、命令もわずか8種類のみであり、実装が容易です。
このため、チューリング完全であることを示すために実装するにはうってつけの言語です。

▼表1 Brainfuckの命令一覧

| 記号 | 処理                                                                         |
|:-----|:------------------------------------------------------------------------------|
| `>`  | ポインタを右に移動                                                           |
| `<`  | ポインタを左に移動                                                           |
| `+`  | ポインタの指すメモリの値をインクリメント                                   |
| `-`  | ポインタの指すメモリの値をデクリメント                                     |
| `[`  |  ポインタの指すメモリの値が0なら対応する `]` の次にジャンプ（ループ起点）|
| `]`  | 対応する `[` にジャンプ（ループ終点）                                       |
| `.`  | ポインタの指すメモリの値をASCII文字として出力                              |
| `,`  | 入力を受け取りポインタの指すメモリに書き込む                               |

ということで、本題にもどりましょう。
ここからはXSLTでBrainfuckの処理系を実装していきます。

## XSLTによるBrainfuckインタプリタの実装

これから紹介するXMLによるBrainfuckインタプリタの実装はGitHubにて公開していますので、適宜参照してみてください。

- [https://github.com/makiuchi-d/bfxslt](https://github.com/makiuchi-d/bfxslt)

インタプリタ本体は `bf.xsl` に実装しています。
この他、 `sample` ディレクトリにサンプルプログラムのXMLファイルをいくつか用意しました。

実行はXSLTプロセッサのコマンドやブラウザで行うことができます。
リポジトリのREADMEにも記載していますが、たとえば `xsltproc` を使用する場合は次のようにコマンドを実行してください。

▼リスト5 xsltprocでの実行
```shell
$ xsltproc bf.xsl sample/hello.xml
Hello, world!
```

### XMLによるBrainfuckコードの表現

XSLTでは、入力はXMLでなくてはなりません。
Brainfuckのコードは単純な命令の列なので、これをXMLで表現します。
また、Brainfuckは入力も受け付けるので、これも同じXMLドキュメントにまとめてしまいましょう。
まずルート要素として `<bf>` タグを配置し、
その中にBrainfuckのコードの `<code>` タグ、入力データの `<input>` タグを入れ子にします。

たとえば、入力として「`Aa`」を読み込み、それぞれ1ずつインクリメントして
「`Bb`」を出力するプログラムはリスト6のようなXMLになります。

▼リスト6 XMLによるBrainfuckコードと入力の表現
```xml
<?xml version="1.0" encoding="utf-8"?>
<bf>
  <input>Aa</input>
  <code>
    <inc/><inc/>
    <loop>
      <dec/><right/><read/><inc/><print/><left/>
      <end/>
    </loop>
  </code>
</bf>
```

元のBrainfuckのコードは「`++[->,+.<]`」[^3]ですが、
この各記号を表2のように定義したXMLタグに置換して記述しています。

[^3]: 単純に「`,+.,+.`」のようにも書けますが、ループの例を示すためにあえて複雑にしています

▼表2 Brainfuckの命令とタグの対応

| 記号    | xmlタグ                 |
|:--------|:-------------------------|
| `>`     | `<right/>`               |
| `<`     | `<left/>`                |
| `+`     | `<inc/>`                 |
| `-`     | `<dec/>`                 |
| `[...]` | `<loop>...<end/></loop>` |
| `,`     | `<read/>`                |
| `.`     | `<print/>`               |

ここで、 `]` は `</loop>` のようにタグを閉じるだけでなく、直前に必ず `<end/>` タグを挿入するようにしました。
この理由は後ほど説明します。

### 実装の方針

XSLTでは、特定のXML要素に対応するテンプレートを定義して、それが呼び出されることで処理が進行します。
インタプリタ実装の `bf.xsl` にはいくつかテンプレートが定義されていますが、
最初に実行されるのはマッチングパターンが最も具体的な、リスト7のテンプレートです。
このテンプレートは、プログラムのXMLの全体を囲んでいる `bf` 要素にマッチして実行されます。

▼リスト7 最初に処理されるテンプレート
```xml
  <xsl:template match="/bf">
    <xsl:variable name="input" select="input"/>
    <xsl:apply-templates select="code/*[1]">
      <xsl:with-param name="ptr" select="0"/>
      <xsl:with-param name="mem"><_0>0</_0></xsl:with-param>
      <xsl:with-param name="input" select="$input"/>
    </xsl:apply-templates>
  </xsl:template>
```

ここではまず、入力にあたる `<input>` 要素を `xsl:variable` を使って変数 `input` に格納しています。
次に `<code>` の中の先頭のBrainfuckの命令にあたる要素に対して `xsl:apply-template` でテンプレートを適用しています。
このときテンプレートにはパラメータとして、ポインタを表す `ptr` 、メモリを表す `mem` 、入力の `input` を `<xsl:with-param>` で渡します。
 `ptr` は数値で初期値は0です。
 `mem` はリスト8のような `<_アドレス>` 要素の列としました。
新たなアドレスにデータを書き込むたびに要素が増えていく形です。

▼リスト8 メモリの表現
```xml
<_0>0</_0>
<_1>10</_1>
<_2>20</_2>
```

ところで、XSLTでは変数は一度定義したら書き換えることができません。
このため、グローバルな変数は使えず、変更を加えた値をパラメータとして次の命令の処理に引き回すことで、状態を更新するようにしています。

各命令のタグのテンプレートはリスト9の形をしています。

▼リスト9 各命令のテンプレートの基本形
```xml
  <xsl:template match="命令のタグ名">
    <xsl:param name="ptr"/>
    <xsl:param name="mem"/>
    <xsl:param name="input"/>

    <!-- 各命令固有の処理 -->

    <xsl:apply-templates select="following-sibling::*[1]">
      <xsl:with-param name="ptr" select="$ptr"/>
      <xsl:with-param name="mem" select="$mem"/>
      <xsl:with-param name="input" select="$input"/>
    </xsl:apply-templates>
  </xsl:template>
```

 `xsl:param` で指定されているとおり、パラメータとして `ptr` 、 `mem` 、 `input` を受け取ります。
そして各命令固有の処理をしたあと、次の命令に進むのですが、 `following-sibling::*[1]` によって現在処理している要素の次の兄弟要素、
つまり次の命令にあたる要素を指定して `xsl:apply-templates` で再帰的にテンプレートを適用します。
こうすることで、次の命令の要素の名前とマッチするテンプレートが選ばれて処理され、これを繰り返すことでプログラムが順次処理されていくことになります。

### 各命令の実装

それでは各命令の処理をするテンプレートを見ていきましょう。

#### ポインタの移動： `right, left`（`>` `<`）

リスト10はポインタを右に移動する `<right/>` の処理をするテンプレートです。
次の命令に進む `xsl:apply-templates` に渡すパラメータのうち、 `ptr` の値を `"$ptr + 1"` とすることで、
次の処理ではポインタが移動した状態となります。
他のパラメータの `mem` と `input` は受け取ったものをそのまま次の命令の処理に渡しています。

▼リスト10 right命令のテンプレート
```xml
  <xsl:template match="right">
    <xsl:param name="ptr"/>
    <xsl:param name="mem"/>
    <xsl:param name="input"/>

    <xsl:apply-templates select="following-sibling::*[1]">
      <xsl:with-param name="ptr" select="$ptr + 1"/>
      <xsl:with-param name="mem" select="$mem"/>
      <xsl:with-param name="input" select="$input"/>
    </xsl:apply-templates>
  </xsl:template>
```

ポインタを左に移動する `<left/>` は、マッチングパターンを `"left"` とし、
次に渡す `ptr` の値を `"$ptr - 1"` とするだけで実現できます。

#### メモリの値の加減算： `inc, dec`（`+` `-`）

リスト11は、 `<inc/>` の処理、つまり現在のポインタの指すメモリの値を1増加させるテンプレートです。
まず値を取り出し、値を更新したメモリを生成し、次の命令のテンプレートを呼び出すという流になっています。

それぞれの処理がどう実現されているか見ていきましょう。

▼リスト11 inc命令のテンプレート
```xml
  <xsl:template match="inc">
    <xsl:param name="ptr" />
    <xsl:param name="mem"/>
    <xsl:param name="input"/>

    <xsl:variable name="key" select="concat('_', $ptr)"/>
    <xsl:variable name="val" select="sum(exsl:node-set($mem)/*[name()=$key])"/>

    <xsl:variable name="mem">
      <xsl:call-template name="write-val">
        <xsl:with-param name="mem" select="$mem"/>
        <xsl:with-param name="key" select="$key"/>
        <xsl:with-param name="val" select="$val + 1"/>
      </xsl:call-template>
    </xsl:variable>

    <xsl:apply-templates select="following-sibling::*[1]">
      <xsl:with-param name="ptr" select="$ptr"/>
      <xsl:with-param name="mem" select="$mem"/>
      <xsl:with-param name="input" select="$input"/>
    </xsl:apply-templates>
  </xsl:template>
```

まず最初に値を取り出す処理として、リスト12の部分で変数 `key` と `val` を定義しています。

▼リスト12 keyとvalueの定義
```xml
    <xsl:variable name="key" select="concat('_', $ptr)"/>
    <xsl:variable name="val" select="sum(exsl:node-set($mem)/*[name()=$key])"/>
```

 `key` は `'_'` とポインタの値を結合したもので、これがポインタの指す、 `mem` の中の要素名になります。
 `val` の定義では、 `mem` の中のノードの集合から、 `key` と同じ名前の要素を取り出しています。
要素が存在しなかったときに `0` となるように、 `sum` 関数を利用しています。
一番最初に `mem` の初期値として `<_0>0</_0>` を用意していたのは、 `mem` の中身をノードの集合にしておくためです。

続いてこれらの値を使って、値を更新した状態のメモリを新たに作り、変数 `mem` を定義します[^4]。
新たなメモリを作る処理は他の命令でも利用するので、リスト13のようにテンプレートで行っています。

[^4]: XSLTでは同じ名前の変数を同じスコープでは再定義できないのですが、この時点での`mem`はテンプレートのパラメータでありスコープが異なるので、同じ名前で定義できます

▼リスト13 値を書き込んだメモリを生成するテンプレート
```xml
  <xsl:template name="write-val">
    <xsl:param name="mem"/>
    <xsl:param name="key"/>
    <xsl:param name="val"/>

    <xsl:for-each select="exsl:node-set($mem)/*[name()!=$key]">
      <xsl:copy-of select="."/>
    </xsl:for-each>
    <xsl:element name="{$key}">
      <xsl:value-of select="$val"/>
    </xsl:element>
  </xsl:template>
```

このテンプレートでは、最初に `xsl:for-each` を使って、与えられた `mem` のうち要素名が `key` ではないものをすべて `xsl:copy-of` でコピーしています。
その後に続ける形で、 `key` の名前の要素を作り、内容を `val` に設定しています。
この方法では要素の順序が書き換えるたびに入れ替わってしまうのですが、読み取るときには要素名でアクセスするので問題ありません。

 `<inc/>` の処理では、このテンプレートに渡すパラメータは現在のメモリ `mem` と書き込む場所の `key` 、そして `val` は `"$val + 1"` のように1加算した値となっていました。
これによって、 `key` の場所の値を `1` 増やしたメモリが生成されるわけです。

最後にこの `mem` を次の命令のテンプレートに渡せば `<inc/>` の処理は完了です。
 `<dec/>` も同じ処理の流れで、加算していたところを `"$val - 1"` とするだけで実現できます。

#### ループ： `loop, end`（`[ ]`）

Brainfuckの `[` は、ポインタの指すメモリの値が0なら対応する `]` の次の命令にジャンプするという命令で、
 `]` は対応する `[` に戻るという命令です。
つまり、ポインタの指すメモリの値が0でない間 `[` と `]` の間にある命令が繰り返し実行されます。

リスト14が今回実装した `[` に相当する `<loop>` を処理するテンプレートです。
メモリの値を読み取って `val` とする部分は `inc` の処理と同じです。
その後、 `xsl:choose` によって、 `val` の値に応じて分岐します。
 `val` が0ではないとき、次に実行する要素として `<loop>` の内側の要素の先頭のものを `"*[1]"` で指定します。
一方それ以外のときは、 `<loop>` の外にある次の要素を `"following-subling::*[1]` で指定します。
このように、 `[` と `]` の対応関係を `<loop>` のネストで表現しているので、ジャンプ先を簡単に指定できます。

▼リスト14 loop命令のテンプレート
```xml
  <xsl:template match="loop">
    <xsl:param name="ptr"/>
    <xsl:param name="mem"/>
    <xsl:param name="input"/>

    <xsl:variable name="key" select="concat('_', $ptr)"/>
    <xsl:variable name="val" select="sum(exsl:node-set($mem)/*[name()=$key])"/>

    <xsl:choose>
      <xsl:when test="$val != 0">
        <!-- 繰り返す: 子要素の先頭に進む -->
        <xsl:apply-templates select="*[1]">
          <xsl:with-param name="ptr" select="$ptr"/>
          <xsl:with-param name="mem" select="$mem"/>
          <xsl:with-param name="input" select="$input"/>
        </xsl:apply-templates>
      </xsl:when>
      <xsl:otherwise>
        <!-- 繰り返し終了: 次の要素に進む -->
        <xsl:apply-templates select="following-sibling::*[1]">
          <xsl:with-param name="ptr" select="$ptr"/>
          <xsl:with-param name="mem" select="$mem"/>
          <xsl:with-param name="input" select="$input"/>
        </xsl:apply-templates>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
```

ループの終わりは、 `<end/>` を置いてから `</loop>` のように閉じています。
この `<end/>` を処理するテンプレートをリスト15に示します。

▼リスト15 end命令のテンプレート
```xml
  <xsl:template match="end">
    <xsl:param name="ptr"/>
    <xsl:param name="mem"/>
    <xsl:param name="input"/>

    <xsl:apply-templates select="parent::node()">
      <xsl:with-param name="ptr" select="$ptr"/>
      <xsl:with-param name="mem" select="$mem"/>
      <xsl:with-param name="input" select="$input"/>
    </xsl:apply-templates>
  </xsl:template>
```

このテンプレートでは、次に処理する要素として親ノード、つまり自身を包んでいる `<loop>` を `"parent::node()"` で指定します。
パラメータはここまで引き継がれてきた `ptr` 、 `mem` 、 `input` を渡します。
こうすることで、次に実行される `<loop>` は、最新のメモリ状態を元にジャンプ先を分岐できるようになります。
この `<end/>` が無い場合、親の `<loop>` は最初に実行された時点のポインタとメモリの状態しかわからないため、正しく処理を継続できません。
また、この実装では `end` を書き忘れてしまうと、親の `<loop>` に処理を戻すことができず終了してしまいます。
これが `<end/>` を挿入する理由です。

#### 出力： `print`（`.`）

Brainfuckでの `.` は、ポインタの指すメモリの値をASCIIコードとして出力します。
リスト16は `<print/>` 命令を実行するテンプレートです。
メモリの値を取得する方法は他の命令と同様に、変数 `val` に値を保存します。
その後 `<xsl:choose>` と `<xsl:when>` で `val` の値ごとに分岐してASCIIコードに該当する文字を出力しています。

▼リスト16 print命令のテンプレート
```xml
  <xsl:template match="print">
    <xsl:param name="ptr"/>
    <xsl:param name="mem"/>
    <xsl:param name="input"/>

    <xsl:variable name="key" select="concat('_', $ptr)"/>
    <xsl:variable name="val" select="sum(exsl:node-set($mem)/*[name()=$key])"/>

    <xsl:choose>
      <xsl:when test="$val=9"><xsl:text>&#9;</xsl:text></xsl:when> 
      <xsl:when test="$val=10"><xsl:text>&#10;</xsl:text></xsl:when>
      <xsl:when test="$val=13"><xsl:text>&#13;</xsl:text></xsl:when>
      <xsl:when test="$val=32"><xsl:text
                          disable-output-escaping="yes"> </xsl:text></xsl:when>
      <xsl:when test="$val=33">!</xsl:when>
      (中略)
      <xsl:when test="$val=125">}</xsl:when>
      <xsl:when test="$val=126">~</xsl:when>
      <xsl:otherwise>&amp;#<xsl:value-of select="$val"/>;</xsl:otherwise>
    </xsl:choose>

    <xsl:apply-templates select="following-sibling::*[1]">
      <xsl:with-param name="ptr" select="$ptr"/>
      <xsl:with-param name="mem" select="$mem"/>
      <xsl:with-param name="input" select="$input"/>
    </xsl:apply-templates>
  </xsl:template>
```

XSLT2.0以降であればASCIIコードと数値を相互変換する関数も提供されていますが、
今回対象としているのはXSLT1.0なので愚直に値ごとに分岐するようにしました。
また、XSLT1.0では扱える制御文字が `HT(9)` 、 `LF(10)` 、 `CR(13)` に限られているため、
それ以外の制御文字やASCIIコード外の127以降の値は `"&#数値;"` という形式の文字列を出力するようにしました。

#### 入力： `read`（`,`）

Brainfuckの `,` 命令は、入力から1文字受け取り、ポインタが指すメモリ位置にそれをASCIIコードとして書き込みます。
リスト17はこの `<read/>` 命令を処理するテンプレートです。

今回のXSLTの実装では、入力はコードと同じXMLに含まれていて、 `input` パラメータとして引き回されてきました。
この `input` から先頭1文字を取り出してメモリに書き込み、取り出した文字を削除した新しい `input` を次の命令に渡すのがこのテンプレートの処理の流れです。

まず最初に `input` の文字列長を `string-length` 関数を使って確認しています。
もし空であれば入力終了を意味するので、ポインタが指す位置に `EOF` を表す `255` を書き込んだメモリを次のテンプレートに渡します。

 `input` が空でない場合、まず `substring($input, 1, 1)` で先頭1文字を取り出し変数 `c` に保存します。
そして次の命令に渡す `input` も `substring($input, 2)` のように2文字目以降を切り出しておきます。

取り出した先頭文字 `c` は、出力のときと同じように `<xsl:choose>` で文字種ごとに分岐してASCIIコードの数値に変換します。
このとき、扱えない制御文字やASCIIコード外の文字は、すべて `255` とすることにします。
この値を書き込んだメモリと、1文字削った `input` を引数にして、次の命令のテンプレートを呼び出したら完了です。

▼リスト17 read命令のテンプレート
```xml
  <xsl:template match="read">
    <xsl:param name="ptr"/>
    <xsl:param name="mem"/>
    <xsl:param name="input"/>

    <xsl:variable name="key" select="concat('_', $ptr)"/>

    <xsl:choose>
      <!-- inputが空のときは255(EOF)を書き込む -->
      <xsl:when test="string-length($input)=0">
        <xsl:apply-templates select="following-sibling::*[1]">
          <xsl:with-param name="ptr" select="$ptr"/>
          <xsl:with-param name="mem">
            <xsl:call-template name="write-val">
              <xsl:with-param name="mem" select="$mem"/>
              <xsl:with-param name="key" select="$key"/>
              <xsl:with-param name="val" select="255"/>
            </xsl:call-template>
          </xsl:with-param>
          <xsl:with-param name="input" select="$input"/>
        </xsl:apply-templates>
      </xsl:when>

      <!-- inputが空でないとき1文字取り出してメモリに書き込む -->
      <xsl:otherwise>
        <xsl:variable name="c" select="substring($input, 1, 1)"/>
        <xsl:variable name="input" select="substring($input, 2)"/>

        <xsl:variable name="val">
          <xsl:choose>
            <xsl:when test="$c='&#9;'">9</xsl:when>
            <xsl:when test="$c='&#10;'">10</xsl:when>
            <xsl:when test="$c='&#13;'">13</xsl:when>
            <xsl:when test="$c=' '">32</xsl:when>
            <xsl:when test="$c='!'">33</xsl:when>
            (中略)
            <xsl:when test="$c='}'">125</xsl:when>
            <xsl:when test="$c='~'">126</xsl:when>
            <xsl:otherwise>255</xsl:otherwise>
          </xsl:choose>
        </xsl:variable>

        <xsl:variable name="mem">
          <xsl:call-template name="write-val">
            <xsl:with-param name="mem" select="$mem"/>
            <xsl:with-param name="key" select="$key"/>
            <xsl:with-param name="val" select="$val"/>
          </xsl:call-template>
        </xsl:variable>

        <xsl:apply-templates select="following-sibling::*[1]">
          <xsl:with-param name="ptr" select="$ptr"/>
          <xsl:with-param name="mem" select="$mem"/>
          <xsl:with-param name="input" select="$input"/>
        </xsl:apply-templates>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
```

以上で、Brainfuckの8種類の命令をすべて実装することができました。
実際に動くかどうかは、ぜひお手元で確認してみてください。

## まとめと展望

この章では、XSLTによるBrainfuckの処理系の実装例を紹介しました。
実際に実装できたことからXSLTはチューリング完全であり、理論的には任意の計算が可能で、
文書の変換や操作にとどまらない強力なツールになりえる可能性があります。

しかし、これを実用するには多くの課題があります。
実際パフォーマンスも悪く、複雑なプログラム[^5]は途中で強制終了してしまうことも珍しくありません。
また文法も、この章を読んでいただいた方なら感じられたと思いますが、人間が読み書きするのに向いておらず、
デバッグやエラーハンドリングの面でも制約しかありません。
くわえて、XSLT 2.0や3.0がW3Cより勧告[^6]されてすでに何年も経っているのですが、
主要ブラウザでは未だサポートされておらず、今後の発展は期待しにくいでしょう。

[^5]: たとえば、リポジトリの `sample/toupper.xml` はブラウザや `xsltproc` では実行できません。
[^6]: [https://www.w3.org/TR/xslt20/](https://www.w3.org/TR/xslt20/)、[https://www.w3.org/TR/xslt-30/](https://www.w3.org/TR/xslt-30/)

一方でXSLTによるプログラミングでは、パターンマッチングや再帰呼び出しといった宣言型・関数型のパラダイムを強制されることになります。
プログラミング用途としてはまったく実用には向きませんが、文法の厳しさも含めて、奇特な方向けのトレーニングにはうってつけの言語といえるでしょう。
みなさんもぜひXSLTでのプログラミングにチャレンジしてみてください。
