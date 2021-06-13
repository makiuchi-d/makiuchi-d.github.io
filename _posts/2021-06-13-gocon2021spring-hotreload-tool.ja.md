---
layout: post
title: ホットリロードツールの作り方（GoCon 2021 Spring）
---

去る4月24日に開催された[Go Conference Online 2021 Spring](https://gocon.jp/)にて、
「[ホットリロードツールの作り方](https://gocon.jp/sessions/session-b3-l/)」という発表をしました。

<script async class="speakerdeck-embed" data-id="0a3c72815795454aa550c6092b26239a" data-ratio="1.77777777777778" src="//speakerdeck.com/assets/embed.js"></script>

[当日の動画](https://www.youtube.com/watch?v=x4BE6txBIR4&t=228s)もYoutubeでご覧いただけます。

また、発表中で紹介している自作ホットリロードツール「[arelo](https://github.com/makiuchi-d/arelo)」もGitHubで公開しています。

== 発表の補足：容量1チャネルを使ったトリック

当日質問も頂いたのですが、少しわかりにくかったと思うので補足します。
また、[ちょうど裏番組だったセッション](https://gocon.jp/sessions/session-a3-l/)でも似たような方法が
チャネルの活用方法のひとつとして紹介されていました。

```Go
	trg := make(chan struct{}, 1)

	go func() {
		for {
			<-trigger
			select { // (1)
			case trg <- struct{}{}:
			default:
			}
		}
	}()

	for {
		cmd := runCmd()

		select { // (2)
		case <-trg:
		default:
		}
		<-trg // (3)
		<-time.NewTimer(delay).C
		killCmd(cmd)
	}
```

まずチャネル`trg`についてです。
容量（capacity）1で初期化しています。

続いて前半のgoroutineでは、チャネル`trigger`にメッセージが届いたら(1)の`select`文で`trg`へ空の`struct`の投入を試みています。
このとき`trg`は容量が1なので空のときは投入できますが、すでに1つ入っているときは`default`に処理が移り何も投入せず、結果としてメッセージは捨てられます。

次に後半のループでは、コマンドを起動した後(3)で`trg`チャネルにメッセージが届くのを待ち、
メッセージが届いたら一定時間待ってコマンドを停止することを繰り返しています。

このなかで`trg`チャネルを待つ前(3)の前に、(2)の`select`文で`trg`チャネルからメッセージを取り出そうと試みています。
もし`trg`にメッセージが入っているなら取り出され、空なら`default`によりなにもしません。
`trg`は容量1なので、高々1つしかメッセージは入っていません。
つまり、(2)の`select`により`trg`は確実に空になり、(3)で待機することになります。

前半のgoroutineでは、`trg`が空の時しかメッセージを投入できませんでした。
そして、後半のループでは`trg`が必ず空の状態で(3)の待機をしています。
これらにより、(3)で待ち始めてから最初の`trigger`へのメッセージだけが(3)によって取り出され、
次にまた(3)で待ち始めるまでのメッセージは捨てることになります。

== まとめ

裏番組でも言及されていましたが、Goのチャネルは`select`と組み合わせることで真価を発揮します。
そしてContextやタイマーもチャネルになっています。
`select`という糊でこれらをうまく連携させていると、いかにもGoらしいコードだなと個人的には感じます。

ところで、容量付きチャネルと`select-default`を組み合わせるテクニックはとても有用で色々な場面で使われていると思うのですが、なにか名前は付いていないのでしょうか。
知っていたら教えてください。
