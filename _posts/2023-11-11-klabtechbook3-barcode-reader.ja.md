---
layout: post
title: "バーコードリーダーになろう (KLabTechBook Vol.3)"
---

この記事は2018年10月8日に開催された[技術書典5](https://techbookfest.org/event/tbf05)にて頒布した「KLabTechBook Vol.3」に掲載したものです。

現在開催中の[技術書典15](https://techbookfest.org/event/tbf15)オンラインマーケットにて新刊「[KLabTechBook Vol.12](https://techbookfest.org/product/d20GG5Femwp1rTWSveSiHF)」を頒布（電子版無料、紙+電子 500円）しています。
また、既刊も在庫があるものは物理本を[オンラインマーケット](https://techbookfest.org/organization/5654456649646080)で頒布しているほか、
[KLabのブログ](https://www.klab.com/jp/blog/tech/2023/tbf15.html)からもすべての既刊のPDFを無料DLできます。
合わせてごらんください。

[<img src="/images/2023-11-11/ktbv12.jpg" width="40%" alt="KLabTechBook Vol.12" />](https://techbookfest.org/product/d20GG5Femwp1rTWSveSiHF)

--------

近年、バーコードやQRコード[^1]でさまざまな情報を受け渡しする場面が増えてきました。
専用の機械がなくてもスマートフォンで簡単に読み取ることができ、皆さんもよく利用しているのではないでしょうか。

そんな便利なスマートフォンも電池切れや家に忘れてしまいがち。
そんなとき、機械に頼らずとも肉眼で読み取ることができればとても便利ですよね。

ただ、QRコードのような二次元コードは複雑で、慣れていないと読むのがかなり大変です。
そこでまずは比較的単純なバーコードから読めるようになりましょう。

[^1]: QRコードは株式会社デンソーウェーブの登録商標です


## バーコードの規格について

ひと口にバーコードと言っても世の中にはたくさんの規格があります。
この章では、おそらくもっともよく見かけるであろう、EAN（European Article Number）規格のバーコードを扱います。

EANのEはEuropeanの略ですが、ISO/ECI 15420として標準化もされている国際規格で、
一般的な商品を表すバーコードとして世界中で使われています[^2]。
日本国内でもJIS-X-0507として標準化されていて[^3]、
特に国コードが日本（49または45）のもはJAN（Japanese Article Number）と呼ぶこともあります。

EANには13桁のものと8桁のものがありますが、今回は13桁の**EAN-13**を読めるようになりましょう。

[^2]: International Article Numberとも呼ばれます
[^3]: JIS規格は[「日本工業標準調査会」のウェブサイト](http://www.jisc.go.jp/app/jis/general/GnrJISSearch.html)で閲覧できます。

## バーコードの構造

<img src="/images/2023-11-11/barcode.png" width="40%" alt="EAN-13バーコード" />

▲図1 EAN-13バーコード

題材として図1にバーコードを用意しました[^4]。
まずはこの構造を詳しく見ていきます。
機械で読み取れなかった場合に備えて、バーコードの下に内容がそのまま書かれていることが多いですが、
書かれていなかったり破損している場合のためにバーコード本体を読めなくてはなりません。
今回は練習として、答え合わせに利用しながら読み進めてみてください。

[^4]: 出典：[Wikipedia:International_Article_Number](https://en.wikipedia.org/wiki/International_Article_Number)

EAN-13の共通の固定パターンとして、
両側に**標準ガードパターン**、そして中央に**中央ガードパターン**があります。
両端と中央の長く書かれている2本線がそれぞれのガードパターンです。
正確には、標準ガードパターンは「黒・白・黒」中央ガードパターンは「白・黒・白・黒・白」のパターンになっています。
このガードパターンによって、バー1本あたりの幅が分かるようになっています。

中央ガードパターンを挟んで、左半分と右半分にそれぞれ6個の**シンボルキャラクタ**が描かれています。
１個のシンボルキャラクタはバー7本分の幅で、そのまま数値1桁を表しています。

ところでEAN-13は13桁なので、これでは1桁足りません。
実は先頭の1桁は、左側6個のシンボルキャラクタの中に隠されているのです。

それではさっそく、シンボルキャラクタから数値を読み取ってみましょう。

## シンボルキャラクタの読み方

表1がシンボルキャラクタと数値の対応表です。
まずはこの表を覚えなくてはなりません。
数値1つあたり3種類のパターンがあって大変に見えるかもしれませんが、
よく見るとセットAを白黒反転するとセットCに、さらにそれを逆順にするとセットBになります。

▼表1 数字セット

| 数値 | セットA | セットB | セットC |
|:----:|:-------:|:--------:|:-------:|
| 0 | ![0A](/images/2023-11-11/0a.png)<br />3:2:1:1 | ![0B](/images/2023-11-11/0b.png)<br />1:1:2:3 | ![0C](/images/2023-11-11/0c.png)<br />3:2:1:1 |
| 1 | ![1A](/images/2023-11-11/1a.png)<br />2:2:2:1 | ![1B](/images/2023-11-11/1b.png)<br />1:2:2:2 | ![1C](/images/2023-11-11/1c.png)<br />2:2:2:1 |
| 2 | ![2A](/images/2023-11-11/2a.png)<br />2:1:2:2 | ![2B](/images/2023-11-11/2b.png)<br />2:2:1:2 | ![2C](/images/2023-11-11/2c.png)<br />2:1:2:2 |
| 3 | ![3A](/images/2023-11-11/3a.png)<br />1:4:1:1 | ![3B](/images/2023-11-11/3b.png)<br />1:1:4:1 | ![3C](/images/2023-11-11/3c.png)<br />1:4:1:1 |
| 4 | ![4A](/images/2023-11-11/4a.png)<br />1:1:3:2 | ![4B](/images/2023-11-11/4b.png)<br />2:3:1:1 | ![4C](/images/2023-11-11/4c.png)<br />1:1:3:2 |
| 5 | ![5A](/images/2023-11-11/5a.png)<br />1:2:3:1 | ![5B](/images/2023-11-11/5b.png)<br />1:3:2:1 | ![5C](/images/2023-11-11/5c.png)<br />1:2:3:1 |
| 6 | ![6A](/images/2023-11-11/6a.png)<br />1:1:1:4 | ![6B](/images/2023-11-11/6b.png)<br />4:1:1:1 | ![6C](/images/2023-11-11/6c.png)<br />1:1:1:4 |
| 7 | ![7A](/images/2023-11-11/7a.png)<br />1:3:1:2 | ![7B](/images/2023-11-11/7b.png)<br />2:1:3:1 | ![7C](/images/2023-11-11/7c.png)<br />1:3:1:2 |
| 8 | ![8A](/images/2023-11-11/8a.png)<br />1:2:1:3 | ![8B](/images/2023-11-11/8b.png)<br />3:1:2:1 | ![8C](/images/2023-11-11/8c.png)<br />1:2:1:3 |
| 9 | ![9A](/images/2023-11-11/9a.png)<br />3:1:1:2 | ![9B](/images/2023-11-11/9b.png)<br />2:1:1:3 | ![9C](/images/2023-11-11/9c.png)<br />3:1:1:2 |

左半分の6個はセットAまたはセットB、右半分の6個はセットCが使われます。
ガードパターンからだけでは逆さになっているかわからないのですが、
逆さにして読んでしまうとこの表に無いパターンが途中で必ず出てくるので判断できます。

さっそく図1を読んでみましょう。左のガードパターンの次から、白3黒1白1黒2と並んでいるので、セットAの9になります。
その次は白1黒1白2黒3なのでセットBの0ですね。その調子で進めていくと、左側は「A9-B0-B1-A2-A3-B4」になりました。
中央ガードパターンを超えて右側に入ります。
こからはセットCしか出てこないのでもっと簡単です。「1-2-3-4-5-7」になっています。読めましたか？

▼表2 先頭桁の導出

| 数値 | 左半分の数字セット |
|:--:|:------------|
| 0 | A A A A A A |
| 1 | A A B A B B |
| 2 | A A B B A B |
| 3 | A A B B B A |
| 4 | A B A A B B |
| 5 | A B B A A B |
| 6 | A B B B A A |
| 7 | A B A B A B |
| 8 | A B A B B A |
| 9 | A B B A B A |


先頭の1桁は左側6個のシンボルキャラクタに隠されているのでした。
まず左側の6個で、セットA・セットBのどちらが使われていたか書き出してみましょう。
「A-B-B-A-A-B」ですね。
このパターンを表2と照らし合わせると「5」になっています。
これが先頭の1桁です。

こうして無事、「5-901234-123457」の13桁を読み取ることができました。


## チェックデジットの検証

EAN-13では、13桁のうち最後の1桁がチェックデジットになっていて、読み取りミスを検知できるようになっています。

計算方法は次のようになっています:

 1. 先頭の桁はそのまま、2桁目は3倍、3桁目はそのまま、4桁目は3倍、と交互に係数を掛けながら12桁を合計する
 2. 1で合計した値を10で割った余り（*mod* 10）を計算する
 3. 余りが0ならチェックデジットは0、それ以外なら10から余りを引いた値がチェックデジット

この値と最後の1桁の値が一致していなければ、どこかで読み取りミスがあったことがわかります。

それでは「5901234123457」のチェックデジットを検証してみましょう。
まず係数を掛けながら12桁を合計します。

{: align="center"}
5 + 9 × 3 + 0 + 1 × 3 + 2 + 3 × 3 + 4 + 1 × 3 + 2 + 3 × 3 + 4 + 5 × 3 = 83

{: align="center"}
83 *mod* 10 = 3

{: align="center"}
10 - 3 = 7

チェックデジットは7で、最後の1桁と一致しました。
読み取りミスはなかったようです。

## おわりに

EAN-13バーコードから13桁の数値を読み取ることができました。
身の回りのバーコードも読み取ってみてください。
最後に、その数値がどんな意味を持っているかは皆さんへの宿題とします。

これで今日からあなたもバーコードリーダー！


---
### コラム：バーコードの逆向き判定

表1の特定のセットに着目すると、
同じセットの中では逆向きにしたときに重複しないようなパターンが巧妙に選ばれています。
たとえば、セットAの0「3:2:1:1」を逆にした「1:1:2:3」はセットAには含まれていません。

セットBとセットCはお互い逆向きにのパターンになっているため、
逆向きに読んだ場合も対応するパターンがテーブルから必ず見つかってしまいます。
一方でセットAを逆向きにしたセットはテーブルに存在せず、
それが見つかったらバーコード自体が逆向きだと判断できます。
表2を見るとAが含まれないパターンはひとつも無いため、
バーコードが逆向きだった場合、必ずAの逆向きのパターンが見つかります。

ちなみに、EAN-13の元になった規格、UPC-Aは元々12桁で、セットAとセットCしか使われていませんでした。
EAN-13の策定過程で桁数を増やすとき、セットCを逆にしたセットBが新たに加えられましたが、
逆向きかの判定ができなくならないように、注意深く導出テーブルが決められているわけです。

もし入れられる情報をさらに増やそうとして、セットAを逆順にしたセットを追加したり、
先頭桁の導出テーブルにAが出てこないパターンを加えてしまうと、
バーコードが逆向きかどうかの判断できなくなってしまいます。

---
