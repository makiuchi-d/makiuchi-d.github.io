---
layout: post
title: "Go言語クイズ：deferとgoroutine"
---

これは[Goクイズ Advent Calendar 2020](https://qiita.com/advent-calendar/2020/goquiz)の12日目の穴埋め記事です。

次のコードを実行するとどうなるでしょう。

```go
package main

import (
	"runtime"
	"sync"
)

func main() {
	runtime.GOMAXPROCS(1)

	wg := sync.WaitGroup{}
	wg.Add(1)
	go func(wg sync.WaitGroup){
		defer print("A")
		defer print("B")
		defer go print("C")
		defer func() { go print("D") }()

		print("E")
		wg.Done()
	}(wg)
	
	print("F")
	wg.Wait()
	print("G")
}
```

そうです、`defer go print("C")`でコンパイルエラーです。簡単すぎますね。

[Playground](https://play.golang.org/p/rShrAUW3-nt)

GoのSpecの[Defer Statements](https://golang.org/ref/spec#Defer_statements)を見ると、次のように定義されています。

> DeferStmt = "defer" Expression .

`defer`に続けられるのは`Expression`のみです。

ところが、`go print("C")`は`Statement`（`GoStmt`）であって`Expression`ではありません。

## 問題

さて、ここからが問題です。

先程のコンパイルエラーを解消しました。
これを実行するとどうなるでしょう。

（処理系は Go 1.15.6 とします）

```go
package main

import (
	"runtime"
	"sync"
)

func main() {
	runtime.GOMAXPROCS(1)

	wg := sync.WaitGroup{}
	wg.Add(1)
	go func(wg sync.WaitGroup){
		defer print("A")
		defer print("B")
		defer func() { go print("C") }()
		defer func() { go print("D") }()

		print("E")
		wg.Done()
	}(wg)

	print("F")
	wg.Wait()
	print("G")
}
```

1. FEABCD まで表示されてDeadlock
2. FEBADC まで表示されてDeadlock
3. FEBACD まで表示されてDeadlock
4. FEBADCG と表示されて終了

[Playground](https://play.golang.org/p/nykfTiglLyL)

## 解答と解説

<details><summary>解答</summary>
正解： 3. FEBACD まで表示されてDeadlock
</details>

↓

↓

↓

↓

↓

↓

↓

↓

↓

### sync.WaitGroupの使い方

最初にDeadlockするかどうかを考えます。

これは標準ライブラリの[`sync.WaitGroup`](https://golang.org/pkg/sync/#WaitGroup)でごくまれにやってしまうミスの問題です。
ドキュメントには次のようにあり、`Add(1)`したあとコピーして使うことはできません。

> A WaitGroup must not be copied after first use.

今回のコードでは、goroutineで呼び出している無名関数の引数として値渡ししているため、そこでコピーが発生しています。
幸いこのミスは`go vet`で警告されるので、簡単に気づくことができます。
`sync.Waitgroup`を関数に渡すときはかならずポインタ渡ししましょう。

### deferの処理順序

続いて、deferの処理順序を確認します。
[Defer Statements](https://golang.org/ref/spec#Defer_statements)には次のようにあります。

> Instead, deferred functions are invoked immediately before the surrounding function returns, in the reverse order they were deferred.

関数から戻る直前に、**deferされたのと逆順で**実行されるとあります。
なので、今回のコードでは次のように実行されます。

1. `func() { go print("D") }()`
2. `func() { go print("C") }()`
3. `print("B")`
4. `print("A")`

### goroutineのスケジューリング

最後にgoroutineがど順序で呼ばれるかが問題となります。
ただしこれはSpecに定義されているわけではなく、処理系依存です（ごめんなさい）。

現在のGoのオフィシャルバイナリのgoroutineのスケジューラについては、次の記事が大変わかりやすいです。

[Golangのスケジューラあたりの話](https://qiita.com/takc923/items/de68671ea889d8df6904)

問題のコードでは、わざとらしく`runtime.GOMAXPROCS(1)`を呼んでいます。
これにより*P(Processor)*は1つだけになり、goroutineの*キュー*も1つになります。

~~goステートメントが実行された時、そのgoroutineはすぐには実行されずに*キュー*に積まれます。~~
~~そして現在のgoroutineが完了した時、*キュー*に最後に積まれたgoroutineを取り出して処理を始めます。~~
~~（*キュー*と呼ばれていますが、動作はFILOのスタックです）~~

#### (01/07追記)
*キュー* ([`p.runq`](https://github.com/golang/go/blob/go1.15.6/src/runtime/runtime2.go#L589-L592))はスタックではなく正しくキュー（FIFO）でした。

goステートメントはコンパイラにより[`runtime.newproc`](https://github.com/golang/go/blob/go1.15.6/src/runtime/proc.go#L3535-L3564)に置き換えられます。
この関数内で[`runqput`を呼ぶ](https://github.com/golang/go/blob/go1.15.6/src/runtime/proc.go#L3558)ことで新しいgoroutineを*キュー*への追加をするのですが、第三引数`next`が`true`になっています。

[`runtime.runqput`](https://github.com/golang/go/blob/go1.15.6/src/runtime/proc.go#L5148-L5184)では、`next==true`のときは`p.runq`にenqueueするのではなく、[`p.runnext`](https://github.com/golang/go/blob/go1.15.6/src/runtime/runtime2.go#L593-L602)に保存します。
この時すでに`p.runnext`にgoroutineがあるときは、すでにあったほうを`p.runq`にenqueueします。

そして、*キュー*からgoroutineを取り出す[`runtime.punqget`](https://github.com/golang/go/blob/go1.15.6/src/runtime/proc.go#L5261-L5288)では、
まず`p.runnext`にgoroutineがあったらそれを、無かったら`p.runq`からdequeueするようになっています。


以下、結果は同じですが細部の表現を修正しました。

(追記ここまで。以下修正）

ここで問題のコードを見ます。

まず`go func(wg sync.WaitGroup){...`でgoroutineが作られ*キュー*に積まれますがまだ実行されません。
そのまま`print("F")`により画面に**F**が表示され、`wg.Wait()`にたどり着きます。

ここで`main`関数のgoroutineは待機してしまうので、*キュー*に積まれたgoroutineに処理が移ります。
4つの`defer`が処理された後、`print("E")`により**E**が表示されます。
ここで`wg.Wait()`を呼んでいますが、先に説明したように値渡しをしてしまっているため、`main`関数は待機状態のままです。

無名関数が終了したので`defer`を逆順に実行します。
最初の`func() { go print("D") }()`によってgoroutineが作られ~~*キュー*に積まれます。~~
`runqput`され、`p.runnext`にセットされます。
次に`func() { go print("C") }()`でも同様にgoroutineが~~*キュー*に積まれます。~~
`runqput`され、先程の`print("D")`を*キュー*に積み、新たなgoroutineを`p.runnext`にセットします。
続いて`print("B")`、`print("A")`が実行され、画面に**BA**が表示されます。

ここでgoroutineが終了したので、~~*キュー*に最後に積まれたものに処理が移ります。~~
`runqget`により次に実行するgoroutineとして`p.runnext`が取り出されます。
それは`print("C")`でした。画面に**C**が表示されます。
次にまた実行可能なgoroutineを*キュー*から取り出すと、それは`print("D")`で、画面に**D**が表示されます。

ここで実行可能なgoroutineがなくなってしまったので、Deadlockとなり異常終了します。

ということで、正解は3. **FEBACD**と表示されてDeadlock でした。
