---
layout: post
title: GoとテストとインプロセスDB（GoCon mini 2023 in KYOTO）
---


去る12月2日に京都で開催され[Go Conference mini 2023 Winter IN KYOTO](https://kyotogo.connpass.com/event/285351/)にて、
「GoとテストとインプロセスDB」という発表(LT)をしてきました。

<script defer class="speakerdeck-embed" data-id="d36d8e6faf534ce492b48fc7df5937bb" data-ratio="1.7772511848341233" src="//speakerdeck.com/assets/embed.js"></script>

おわかりの通りタイトルは「バカとテストと召喚獣」のパロディです。
スライドのタイトルの「と」を丸背景の白抜きにしてるところは拘りました。
（GoogleスライドからPDF出力すると位置がずれるので逆算した位置にずらして出力したものをSpeakerDeckに上げたりしてます）

## 発表の概要

DB問い合わせを含むロジックのユニットテストは悩みの種です。
会場でも頷いてくれる方々がそこそこいらっしゃいました。

このようなテストではDBのモックを使ったり本物のDBをDockerで動かすこともよくありますが、
この発表ではプロセス内で動くDBを使う方法に焦点を当てました。
そのようなDBとしてはSQLiteが有名ですが、
GoではMySQL互換の「[go-mysql-server](https://github.com/dolthub/go-mysql-server)」や
PostgreSQL互換の「[ramsql](https://github.com/proullon/ramsql)」といった
ピュアGoで書かれたDBもありテストに便利そうです。

go-mysql-serverはインプロセスで動かすためのDriverがあまりメンテナンスされていなかったので、
修正PRをいくつも出すことになったりしました。
使いたい人が直して使えるようにできることこそがOSSの良いところですね。

くわえて、go-mysql-serverをテストで使いやすくするラッパ「[testdb](https://github.com/makiuchi-d/testdb)」を紹介しました。

このあたりの話は「[SQLを含めたユニットテストにgo-mysql-serverが便利](/2023/08/12/go-mysql-server.ja.html)」にも書いています。

## go-mysql-serverの現状

トランザクションのサポートがないことについて、発表の中でもデメリットとして紹介しました。
今もまだサポートされているわけではないですが、今後できるようになりそうな変更が入り始めているので、期待できるかもしれません。

一方その影響でDriverの動作がまた怪しくなっています。
testdbでは[`sql.Open`](https://pkg.go.dev/database/sql#Open)を使わないようにして問題を回避していますが、もう少し原因を追いかけてみたいと思います。


## 謝辞

最後に、運営のKyoto.goおよび一般社団法人Gophers Japanの皆様、素晴らしいイベントをありがとうございました。
久しぶりのオフラインの発表、そして懇親会もあり、いろいろな方とお話でき有意義な時間でした。
また「mini」の名の通りGo Conferenceに比べて小規模な分、トラックが1本のみで全ての発表を見ることができ、とても満足度が高かったです。

そして2次会として、株式会社はてな様のオフィスにお邪魔させていただきました。
休日の深夜、それも大人数という非常識極まりない訪問でも快く受け入れていただける懐の広さには感服するばかりです。

今回ご挨拶できた方もそうでない方も、次回またよろしくおねがいします。
