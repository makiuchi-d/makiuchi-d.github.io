---
layout: post
title: "BashとZshの \"**\" (globstar) の挙動の違い"
---

## "**" (globstar) とは

globの構文として使える、0個以上のディレクトリに再帰的にマッチするワイルドカードです。
例えば、`a/**/z`は `a/z`, `a/b/z`, `a/b/c/z`... にマッチします。

元々はzshで実装され、Zsh 2.2で`**`の形式として定着したようです[^1]。
その後、Bash 4.0でもglobstarオプションを有効にすることで使えるようになりました[^2]。

globの構文はPOSIX.2にも定義されていますが、そこには`**`は含まれていないため、処理系によって動作がまちまちになっています。
この記事では、bashとzshでの挙動の違いを紹介します。

[^1]: [再帰globパターン **/ の元祖は zsh なのか、調べてみた - hkoba blog](https://hkoba.hatenablog.com/entry/2016/02/10/230206)
[^2]: [「bash 4.0」リリース、4年7カ月ぶりのメジャー・アップデート - スラド](https://srad.jp/story/09/02/24/1538237/)

## BashとZshでの挙動の違い

次のようにディレクトリとファイルを用意し、bash、zshそれぞれでマッチするかどうかを確かめ、結果を表にまとめました。
環境はdocker ubuntu:focal、bash 5.0.16、zsh 5.8です。

```
.
|-- fileA
`-- subA/
    |-- fileB
    `-- subB/
        |-- fileC
        `-- subC/
```

| pattern  | fileA | subA | subA/fileB | subA/subB | subA/subB/fileC | subA/subB/subC |
|:---------|:-----:|:----:|:----------:|:---------:|:---------------:|:--------------:|
| \*       | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× |
| \*/      | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× |
| \*/\*    | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× |
| \*/\*/   | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× |
| \*\*     | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;◯<br>zsh&nbsp;◯ | **<font color="red">bash&nbsp;◯<br>zsh&nbsp;×</font>** | **<font color="red">bash&nbsp;◯<br>zsh&nbsp;×</font>** | **<font color="red">bash&nbsp;◯<br>zsh&nbsp;×</font>** | **<font color="red">bash&nbsp;◯<br>zsh&nbsp;×</font>** |
| \*\*/    | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ |
| \*\*/\*  | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;◯<br>zsh&nbsp;◯ |
| \*\*/\*/ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ |
| \*/\*\*  | bash&nbsp;×<br>zsh&nbsp;× | **<font color="red">bash&nbsp;◯<br>zsh&nbsp;×</font>** | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;◯<br>zsh&nbsp;◯ | **<font color="red">bash&nbsp;◯<br>zsh&nbsp;×</font>** | **<font color="red">bash&nbsp;◯<br>zsh&nbsp;×</font>** |
| \*/\*\*/ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ |
| s\*\*    | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× |
| s\*\*/   | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;◯<br>zsh&nbsp;◯ | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× | bash&nbsp;×<br>zsh&nbsp;× |

zshでは`**/`の形のときのみ再帰的にディレクトリとマッチしているのに対し、bashでは`**`でも再帰的に、ディレクトリだけでなくファイルにもマッチしています。
また、どちらの場合もパターン末尾が`/`のときはディレクトリにのみマッチします。

もし特定ディレクトリ以下のすべてのファイル・ディレクトリにマッチさせたい場合、bashでは`**`でもマッチしますが、zshでは`**/*`としなければなりません。

## その他の処理系について

いくつかの言語では標準パッケージとして`**`をサポートしたglobを提供しています。
手元で調べたところ、pythonはbashと、rubyはzshと同様の動きをしますが、Haskellはまたちょっと違う動作をしていました。

`**`の挙動は明確に規格化されているわけではないため、混乱した状況は続きそうです。
