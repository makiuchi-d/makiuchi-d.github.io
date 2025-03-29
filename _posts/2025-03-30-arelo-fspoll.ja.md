---
layout: post
title: "WSL2のファイル変更監視問題とfspollを作った話"
---

[arelo](https://github.com/makiuchi-d/arelo)ではファイルの更新検知に[fsnotify](https://pkg.go.dev/github.com/fsnotify/fsnotify)を利用していますが、
WSL2で利用している時にWindows側ファイルシステムのイベントが受け取れない問題がありました。
[この問題はWSL2の制限として知られています](https://github.com/microsoft/WSL/issues/4739)。

そこで、このような環境でも動作するようにするために、
ファイルの更新日時などを定期的にチェックして変更を検知するポーリング機能を追加することにしました。

この記事では、ポーリング機能実装時に気をつけていたgoroutineの扱い方について紹介します。

## 既存の解決策とその問題

areloと同じく自動リロードを提供する[air](https://github.com/air-verse/air)は既にポーリング機能を実装していました。
areloでも同様に実装しようとしましたが、airがポーリングに利用している[fugoのfilenotify](https://pkg.go.dev/github.com/gohugoio/hugo/watcher/filenotify)は
fsnotifyと互換がありますが、いくつかの点で挙動が異なっていました。

1. `filePoller.Close()`したあとEvents・Errorsチャネルがcloseされない
2. ディレクトリを監視している時、そのディレクトリのchmodイベントが発火しない
3. 監視対象が削除されたり`filePoller.Remove()`を呼んでも監視が止まらない

このうち1は、areloではCloseを呼ばないので問題ありません。
2についてもディレクトリのchmodイベントでリロードしたいケースはあまり多くないので許容範囲でしょう。
しかし、3が問題でした。

airやareloではディレクトリを再帰的に監視対象として追加していきます。
そしてfilenotifyでは監視対象を追加するごとにgoroutineを立ち上げていて、それが消えることはありません。
つまり、ディレクトリの作成・削除あるいはリネームを繰り返すたび、どんどんgoroutineが増えていきます。
自動リロードツールを利用するのは主に開発の場面なので、gitのブランチ切り替えでディレクトリの作成・削除が頻発することは普通にありえるでしょう。
これは致命的です。

他に良さそうなライブラリもぱっとは見つからなかったので、じゃあ自作するしかありませんね！
ということで、fsnotifyと互換のファイルポーリングライブラリ [github.com/makiuchi-d/arelo/fspoll](https://pkg.go.dev/github.com/makiuchi-d/arelo/fspoll) を実装しました。

## goroutineのリーク防止

fspollもfilenotifyと同じく監視対象ごとにgoroutineを立ち上げます。
ですが監視対象の削除やRemove呼び出しでgoroutineを確実に停止するようにしました。
また、Poller.Closeの呼び出し時にはすべての監視goroutineを停止します。

このような親子関係のあるgoroutine制御こそ[context.Context](https://pkg.go.dev/context)の出番です。
しかし、fsnotifyには外部からContextを渡すインターフェイスがありません。
Goのベストプラクティスからは外れますが、fspollではPoller構造体初期化時に親となるContextとそれを停止するためのCancelFuncを作成し、そのまま保持するようにしました。

```go
	ctx, cancel := context.WithCancel(context.Background())
	p := &Poller{
		events:     make(chan Event, 1),
		errors:     make(chan error, 1),
		interval:   interval,
		ctx:        ctx,
		cancel:     cancel,
		cancellers: make(map[string]context.CancelFunc),
	}
```

監視goroutineを立ち上げるときは、context.WithCancelで子ContextとCancelFuncを作成します。
このCancelFuncはRemoveする時用にPollerが保持しておきます。
また、監視goroutineが終了するときに確実にCancelFuncも削除します。

```go
	ctx, cancel := context.WithCancel(p.ctx)
	p.cancellers[name] = cancel

	ready := make(chan struct{})
	p.wg.Add(1)
	go func() {
		defer p.wg.Done()
		if fi.IsDir() {
			p.pollingDir(ctx, name, fi, ready)
		} else {
			p.pollingFile(ctx, name, fi, ready)
		}
		cancel() // to prevent deadlock: ready might not be closed
		_ = p.Remove(name)
	}()
```

polling関数の中ではいくつかのチャネルの読み書きを行いますが、その全てで必ずcontext.Doneと合わせてselectし、
Context完了時は速やかにreturnしてgoroutineを終了します。

```go
	t := time.NewTicker(p.interval)
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}

		...略...

		if m, s := fi.ModTime(), fi.Size(); m != modt || s != size {
			modt = m
			size = s
			if !p.sendEvent(ctx, name, Write) {
				return
			}
		}
	}
```
```go
func (p *Poller) sendEvent(ctx context.Context, name string, op Op) bool {
	if p.isClosed() {
		return false
	}
	select {
	case <-ctx.Done():
		return false
	case p.events <- Event{Name: name, Op: op}:
		return true
	}
}
```

チャネルの読み書きは容易に待ち状態になりgoroutineリークの原因になる部分なので、
必ずselectと組み合わせてContext完了時に確実に抜けられるようにしましょう。

## チャネルのclose

fsnotifyではWatcher.Close呼び出し後、EventsとErrorsのチャネルがcloseされます。
fspollのPollerもfsnotifyと挙動を合わせてチャネルをcloseするようにしました。

このとき監視goroutineが動いているままcloseしてしまうと、closeしたチャネルに書き込もうとしてpanicする可能性がでてきてしまいます。
これを避けるためにPoller.Close呼び出して親Contextが完了した後、WaitGroupを使って監視goroutineがすべて終了するのを待ってcloseしています。

```go
	go func() {
		<-p.ctx.Done()
		p.wg.Wait()
		close(p.events)
		close(p.errors)
	}()
```

## 終わりに

fspollを実装したことで、areloでもWSL2環境でのファイル変更検知ができるようになりました。
fsnotifyとの互換性も高く、goroutineのリークもしないよう気を使った堅牢なものになっています。
この実装の工夫は基本に忠実なやり方なので、ぜひ参考にしてみてください。
