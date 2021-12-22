---
layout: post
title: "QRコードを1ピクセルずつ消していく闇のゲームの攻略法"
---

<blockquote class="twitter-tweet"><p lang="ja" dir="ltr">QRコードを1人1ピクセルずつ消していき、リーダーで認識できなくなったら負けという闇のゲームで、全てのスターチップを失いました <a href="https://t.co/8N4IC4AyRI">pic.twitter.com/8N4IC4AyRI</a></p>&mdash; あさくら🍃🥜 (@asakura_dev) <a href="https://twitter.com/asakura_dev/status/1472604567502475265?ref_src=twsrc%5Etfw">December 19, 2021</a></blockquote> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>

<blockquote class="twitter-tweet"><p lang="ja" dir="ltr">QRコードを肉眼で読めるので（）、固定パターンを避けて同じブロック内だけ消していくという攻略ができるのです。そして誤り訂正レベルも見えるのであとどれだけ消したら死ぬかもわかってしまうのです。 <a href="https://t.co/xzFuO46vtv">https://t.co/xzFuO46vtv</a></p>&mdash; MakKi (@makki_d) <a href="https://twitter.com/makki_d/status/1472894353740017665?ref_src=twsrc%5Etfw">December 20, 2021</a></blockquote> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>

固定パターンを避けてワード単位で消すだけでは全然攻めきれてないので、ちゃんとした攻略法を書き残しておきます。

## QRコードの構造

まずは構造を知らねばお話にならない。
とりあえず[Wikipedia](https://ja.wikipedia.org/wiki/QR%E3%82%B3%E3%83%BC%E3%83%89)から画像を拝借。

![QRコードの構造](https://upload.wikimedia.org/wikipedia/commons/1/1d/QR_Code_Structure_Example_3.svg)

リプライで何人か書いているように、最低限の固定パターンは消さないほうが良いのは間違いない。
まずは固定パターン以外をどう攻めるかがポイント。

## Format情報

まず攻めるべきはFormat情報。
左上のPositionパターンの周りにあるやつのコピーが、右上左下のPositionパターンのところにも配置されている。

[ZXing](https://github.com/zxing/zxing)をはじめ、多くのQRコードリーダーはまず左上のFormat情報を読もうとして、
失敗したら右上左下のものを読もうとする。
なので、右上左下のパターンは全消ししてOK。

さらに残った左上のFormat情報も、BCH符号(15, 5)で符号化されていて、3ピクセルまでは誤り訂正可能なので3つ消せる

## Version情報

バージョン7（45x45）以上の大きいQRコードには18ピクセルのVersion情報が2箇所ある。
（QRコードの「バージョン」はサイズのことを指すぞ！覚えておいてね！）

これもFormat情報と同じく、右上のものと左下のものは全く同じコピー。
つまり片方は全消しできる。
ZXingでは先に右上を読むので、消すなら左下からがよいかも？

そして残った方も、BCH符号(18, 6)なので3ピクセルまで訂正可能。3つ消せる。

## データ+エラーコレクション

いよいよ本命？の一番広い部分。

これらは[リード・ソロモン符号](https://ja.wikipedia.org/wiki/%E3%83%AA%E3%83%BC%E3%83%89%E3%83%BB%E3%82%BD%E3%83%AD%E3%83%A2%E3%83%B3%E7%AC%A6%E5%8F%B7)で誤り訂正できるようになっている。
この符号はワード単位なので、同じワードの中がいくつ消されていても1ワードの誤りとしかカウントされない。
つまり、消すなら同じワードを集中して消すのが鉄則。

![ワード配置](https://upload.wikimedia.org/wikipedia/commons/7/77/QR_Ver3_Codeword_Ordering.svg)

この図のように、2列ずつ8ピクセルで1ワードとして、使用済みの場所を避けながらジグザグに配置されている。

まず手を付けるのは末尾の未使用領域。問有無用で消せる。
あとはできるだけ黒いピクセルの多いワードから消し潰していけばいい。

消せるワードの数はバージョンとエラー訂正レベルで決まる。
Format情報からエラー訂正レベルを読み取って計算すれば良い。
例えばバージョン3のエラー訂正レベルMなら、全部で70ワードなのでその約15%の10ワードまでなら消せる。

## 固定パターン

これ以上は消したら基本的にエラー訂正では回復しきれないところまできたので、固定パターンに手を付ける。
ここからはQRコードリーダーの性能を信じての運試し。

まずAlignmentパターンが沢山ある場合、一番右下以外は消しても大丈夫なことがある。
ちなみにZXingは右下のやつしか見ていない。

Positionパターンは縦横ともに黒白黒白黒が1:1:3:1:1の場所を探せと規格としても書かれている。
見つけてくれると信じて、中央を十字に残すように端の方から消していく。

あとはTimingパターン。
元ツイートのリプライでは何人も大事だから消しちゃダメと言っているけど、実はそんなこと無かったりする。
実際ZXingでは使わずに、PositionパターンとAlignmentパターンだけで歪み補正している。
QRコードリーダーの実装次第にはなるけれど、消しても大丈夫な可能性がある。

## 本当の闇のゲームの始まりだぜ

ここまでやったらもう理論的に消せる場所は残っていないはず。
自分の運命を信じよう。

## おまけ：QRコードジェンガやってみた

<blockquote class="twitter-tweet"><p lang="ja" dir="ltr">多分これが限界。 <a href="https://t.co/42FPIzSfdO">https://t.co/42FPIzSfdO</a> <a href="https://t.co/PfY5sRURgG">pic.twitter.com/PfY5sRURgG</a></p>&mdash; MakKi (@makki_d) <a href="https://twitter.com/makki_d/status/1473343394428899328?ref_src=twsrc%5Etfw">December 21, 2021</a></blockquote> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
