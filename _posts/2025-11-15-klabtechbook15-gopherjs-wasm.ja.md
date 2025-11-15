---
layout: post
title: "GopherJSからWebAssemblyへ: Go-TypeScript連携の再構築 (KLabTechBook Vol. 15)"
---

この記事は2024年11月2日から開催された[技術書典18](https://techbookfest.org/event/tbf18)にて頒布した「[KLabTechBook Vol. 15](https://techbookfest.org/product/xmtJPdPuamKDgrnmkek9pn)」に掲載したものです。

現在開催中の[技術書典19](https://techbookfest.org/event/tbf19)オンラインマーケットにて新刊「[KLabTechBook Vol.16](https://techbookfest.org/product/aVbpmUVUwehW3Mym5rYrzN)」を頒布（電子版無料、紙+電子 500円）しています。
また、既刊も在庫があるものは物理本を[オンラインマーケット](https://techbookfest.org/organization/5654456649646080)で頒布しているほか、
[KLabのブログ](https://www.klab.com/jp/blog/tech/2025/tbf19.html)からもすべての既刊のPDFを無料DLできます。
あわせてごらんください。

[<img src="/images/2025-11-15/ktbv16.png" width="40%" alt="KLabTechBook Vol.16" />](https://techbookfest.org/product/aVbpmUVUwehW3Mym5rYrzN)

--------

KLabのリアルタイム通信システム「[WSNet2](https://github.com/KLab/wsnet2)」はGo言語で開発していますが、
付属の簡易ダッシュボードはTypeScript（TS）で実装しています。
このTSコードからGoで実装した機能を利用するために、[**GopherJS**](https://github.com/gopherjs/gopherjs)を利用していました。

この章では、このGopherJSで直面した問題と **WebAssembly（Wasm）** に置き換えることになった経緯、そして具体的な移行作業について紹介します。

## ことの発端

### WSNet2の技術構成

KLabではオンライン対戦や協力プレイのためのリアルタイム通信システム「WSNet2」を開発・運用しています。
WSNet2のサーバーは、大量の同時接続を効率的に処理するため、平行処理が得意なGo言語で実装しています。

WSNet2には、部屋の情報などを閲覧するための簡易ダッシュボードも付属しており、
こちらはフロントエンド・バックエンドともにTypeScript（TS）で開発しています。
ここで一つ課題がありました。
WSNet2では部屋の情報をネットワークで送受信するために独自のシリアライズフォーマットを採用しており[^1]、
ダッシュボードでこの情報を表示するためにはデシリアライズ処理が必要です。

このデシリアライザはWSNet2サーバー用のGoの実装がすでに存在します。
そこで、同じロジックをTSで再実装するのではなく、@<kw>{GopherJS}を利用することにしました。
GopherJSはGoのコードをJavaScript（JS）にトランスパイルするツールです。
これを使うことで、Goで記述されたデシリアライザをダッシュボードのバックエンドのTSコードから利用できるようにしました。

[^1]: 詳細は KLabTechBook Vol.9「[オンライン対戦を支える独自シリアライズフォーマット]({% post_url 2024-06-02-klabtechbook9-wsnet2-serializer %})」で紹介しています

### GopherJSとGoのバージョン問題

このように便利に使っていたGopherJSでしたが、ある時、問題に直面しました。
WSNet2のサーバーで利用しているライブラリとGoコンパイラをアップデートしたところ、
ダッシュボード側でのGopherJSによるトランスパイルが失敗するようになってしまいました。

GopherJSがサポートするGoのバージョンは厳密に決まっています。
このとき利用していたGopherJSは「1.19.0 beta1 for Go 1.19.13」でした。
しかし、アップデートした一部のライブラリがGo 1.20以降の新しいバージョンを要求していたため、
GopherJSによるトランスパイルができなくなってしまいました。

このままでは、WSNet2サーバー自体の更新も滞ってしまいます。
デシリアライザをTSで再実装することも考えましたが、
ちょうどその頃、Goの公式コンパイラがWasmのサポートを強化しているという話を思い出しました。
WasmであればJSから利用できるので、Goで実装したデシリアライザをWasmにコンパイルすれば、TSからも直接呼び出すことができるはずです。
ということで、これまでGopherJSが担っていた役割を、このGo公式のWasm機能で置き換えることにしました。

## GoのWasmについて

### Wasmとは

Wasmは、ブラウザ上でプログラムを高速に実行するためのバイナリフォーマットで、JSを補完するものとして開発されました。
現在ではブラウザだけに留まらず、Node.jsのようなJSランタイムやwasmtimeといったネイティブWasmランタイムなどでも利用できます。

また、Wasmのフォーマットは標準化されており、C/C++、Rust、Goなど多様なプログラミング言語からコンパイルできます。
さらに、特定のCPUやOSに依存せず動作することから、ポータブルなアプリケーションフォーマットとしても注目されつつあります。

### Wasmのビルド、JS/TSからの利用

まず、Goのコード`hello.go`を用意します（リスト1）。

▼リスト1: hello.go
```go
package main

import "syscall/js"

// hello : JSに公開する関数
func hello(this js.Value, args []js.Value) any {
	return "Hello, " + args[0].String() + "!"
}

func main() {
	// JSのglobalThisにhello関数をセット
	js.Global().Set("hello", js.FuncOf(hello))

	<-(chan struct{})(nil) // main関数を終了させない
}
```

このコードでは、`hello`関数をJSから呼び出せるように`main`関数内で`globalThis`オブジェクトにセットしています。
`main`関数が終了するとエクスポートした関数も利用できなくなるため、nilチャネルを使って永久にブロックしています。

Go 1.24からは`go:wasmexport`ディレクティブによっても関数を公開できるようになりました。
しかし引数や戻り値で利用できる型が限られており、WSNet2のデシリアライザのような複雑なデータ構造を扱うには適さないため、
ここでは従来の`js.FuncOf`を使う方法のみ解説します。
興味のある方はぜひ調べてみてください。

GoでWasmをビルドするには、環境変数でターゲットのOSを`js`、アーキテクチャを`wasm`のように指定します。

```shell
GOOS=js GOARCH=wasm go build -o hello.wasm hello.go
```

このコマンドでは`hello.wasm`という名前でWasmのバイナリを出力しています。
これをNode.jsから利用するには、WebAssembly APIとGoが提供する`wasm_exec.js`[^2]を用いてロード・実行します（リスト2）。

[^2]: `GOROOT`以下の`lib/wasm/wasm_exec.js`にあります（Go 1.23以前は`misc/wasm/wasm_exec.js`）

▼リスト2: hello.js
```js
import "./wasm_exec.js";
import fs from "node:fs";
import path from "node:path";

// wasm_exec.jsで提供されるGoランタイムなどの初期化
const go = new Go();

// hello.wasmをロード
const dir = path.dirname(new URL(import.meta.url).pathname);
const wasm = await WebAssembly.instantiate(
    fs.readFileSync(path.resolve(dir, "hello.wasm")), go.importObject);

// hello.wasm内のmain関数を実行
go.run(wasm.instance);

// hello.wasmでglobalThisにセットしたhello関数を呼び出す
console.log(globalThis.hello("world"));
```

この`hello.js`と先程ビルドした`hello.wasm`、Goのコンパイラに付属している`wasm_exec.js`を同じディレクトリに置き、
Node.js[^3]で実行すると次のようにhello関数の実行結果が得られます。

[^3]: Node.js v23.11.0で確認しています

```shell
$ node hello.js
Hello, world!
```

このように、GoでWasmバイナリをビルドし、wasm_exec.jsとWebAssembly APIを利用して、JSやTSからGoで実装した関数を呼び出せます。

### GopherJSとの違い

GopherJSもWasmも、GoのコードをJS/TS環境で実行するという目的は同様ですが、そのアプローチと特性は大きく異なります。

#### トランスパイル vs コンパイル

GopherJSはGoのソースコードを等価なJSコードにトランスパイルします。つまり、最終的に実行されるのはJSのコードです。
一方Wasmでは、GoのソースコードはWebAssemblyバイナリにコンパイルされます。実行時には実行環境のWasmエンジンがこのバイナリを解釈・実行します。

どちらの場合もGoのランタイム実装やそれをエミュレートするコードが含まれるため、ファイルサイズはある程度大きくなります。
ただ、Wasmの場合はコンパイルオプションによる最適化やTinyGoのような小さなバイナリを生成できるコンパイラを使うことでサイズを削減できる余地があります。

またパフォーマンス面では、計算の効率だけであれば事前に最適化されやすいWasmのほうが有利になる傾向があります。
しかしWasmでは、JSとWasm間でデータをやり取りする際に、境界をまたぐためのコンテキストスイッチや値の変換のオーバーヘッドが生じます。
そのため、GoとJSの間で頻繁にやりとりが発生する場合は、境界を超える必要のないGopherJSのほうが有利になることもあります。

#### GoとJSの連携

GopherJSでは、GoのコードからのJSのオブジェクトや関数へのアクセスは[GopherJS独自の`js`パッケージ](https://pkg.go.dev/github.com/gopherjs/gopherjs/js)を通して行います。
また、プリミティブな型だけでなくGoの`struct`型、`map`や`slice`といった複合型も、
JSのオブジェクトや配列と相互変換されるように見せてくれるため、そのまま扱えます。
加えて、ユーザー定義の`struct`とメソッドも`js.MakeWrapper`関数を利用することで簡単にJSからも利用できます。

一方Wasmでは、標準の`syscall/js`パッケージを通してJSのグローバルオブジェクトや関数にアクセスします。
JSの値はGo側では`js.Value`型として受け渡されるため、利用するときに開発者は明示的に変換処理を呼び出すことになります。
特に`slice`や`map`、ユーザー定義型の場合は、明示的にコピーや`map[string]any`型への詰め替えを行い、JSのオブジェクトに変換するような実装が必要です。

#### モジュールシステム

JSからGoの実装を利用するには、GopherJSの生成したJSファイルを`require`したり、WasmファイルをWebAssembly APIでロードする必要があります。

JSで他のJSファイルをモジュールとして読み込む方法は、Node.jsで伝統的に使われてきた **CommonJS（CJS）** と、
新たにブラウザでの利用も考慮して非同期処理に対応し標準規格としても策定されている **ES Modules（ESM）** の2つの形式があります。

GopherJSは元々Node.jsをターゲットにしていたこともありCJS形式です。
CJSの`require`は同期的な処理が前提となっており、GopherJSの出力したJSファイルも読み込んだらすぐに使えるようになります。

一方で、WasmをロードするためのWebAssembly APIは基本的に非同期処理として提供されています。
GopherJSのときと同じような使い方、つまりWasmをロードするJSファイルを読み込んですぐ使えるようにするためには、
トップレベルでawaitを使ってロードが完了するのを待つのが簡単な方法です。
トップレベルawaitを使うためにはESMにする必要があります。

ここでひとつ問題があります。
ESM側でCJSのモジュールを読み込むのは簡単ですが、逆にCJS側でESMのモジュールを読み込むのは困難です。
今回GopherJSからWasmに移行したいダッシュボードはCJSで作られていました。
このため、WasmをロードするモジュールをESMにしたいがために、プロジェクト全体をESMにしなければなりませんでした。
この変更作業の詳細についても、後ほど紹介します。

## GopherJSからWasmへの移行

前置きが長くなりましたが、ここからはGopherJSからWasmへの移行にあたって、具体的にどのような変更を行ったのか紹介します。
実際のWSNet2リポジトリのPullRequestもあわせてご覧ください。

 * [https://github.com/KLab/wsnet2/pull/91](https://github.com/KLab/wsnet2/pull/91)

### Goのコードの変更

GopherJSやWasmでビルドするためのGoのコードでは、
WSNet2のダッシュボードで利用する`binary.UnmarshalRecursive`関数をJS側にエクスポートします。
この関数の型はバイト列を受け取り、ネストされたオブジェクトにデシリアライズするものです。

#### GopherJS向けの実装

GopherJSでは関数の引数や戻り値はシンプルな`struct`や文字列キーの`map`であれば、
それらがネストされていてもそのまま対応する形のJSのオブジェクトに変換されます。
このため、Node.jsで利用できるようにするにはリスト3のように`main`関数の中で
`UnmarshalRecursive`関数をCJSのモジュールとしてエクスポートするだけでよく、非常に簡単です。

▼リスト3: GopherJSのためのGoの実装（main.go）
```go
package main

import (
	"github.com/gopherjs/gopherjs/js"
	"wsnet2/binary"
)

func main() {
	ex := js.Module.Get("exports")
	ex.Set("UnmarshalRecursive", binary.UnmarshalRecursive)
}
```

これをGopherJSで次のようにビルドし、生成された`binary.js`をダッシュボードのソースの中にコピーして利用します。
GopherJSの対応するGoよりも新しいGoを使用していることが普通でしょうから、
`GOPHERJS_GOROOT`環境変数で対応するバージョンのパスを指定する必要があります。

```shell
GOPHERJS_GOROOT="$(go1.19.13 env GOROOT)" gopherjs build -o binary.js main.go
```

#### Wasm向けの実装

WasmでJSに公開できる関数の引数は`js.Value`型なので、
値を取り出し適切な型に変換してから`UnmarshalRecursive`に渡すラッパー関数を定義して、こちらを公開します。
また戻り値は`any`型ですが、実際に返せるのはプリミティブな型やそれらを含む`map`や`slice`などに限られます。
独自型を含むような値を直接返すことができません。

一方、`UnmarshalRecursive`関数でデシリアライズした値は独自型を含むネストした形になっています。
そのような値をJS側に返すには、再帰的に一つ一つ`map`に詰め直すことが必要な場面です。
ただ幸い、この値はもともとJSONへシリアライズできるような実装になっていました。
このため、ラッパー関数では値をまるごとJSONに変換して文字列として返し、JS側でデコードして独自型を含む値に戻すようにしました。

▼リスト4: WasmのためのGoの実装（main.go）
```go
package main

import (
	"encoding/json"
	"syscall/js"
	"wsnet2/binary"
)

func main() {
	js.Global().Set("binary", map[string]any{
		"UnmarshalRecursive": js.FuncOf(unmarshalRecursive),
	})
	<-(chan struct{})(nil)
}

// unmarshalRecursive unmarshals binary formatted custom props.
// binary.UnmarshalRecursive(arg number[]): { val: string, err: string }
func unmarshalRecursive(this js.Value, args []js.Value) (ret any) {
	defer func() { // panicしたとき、errorを取り出してretに詰めて返す
		if err := recover(); err != nil {
			ret = map[string]any{
				"val": "",
				"err": "UnmarshalRecursive: " +
					err.(error).Error(),
			}
		}
	}()

	// 引数を[]byteに詰め直す
	arg := args[0]
	len := arg.Length()
	b := make([]byte, len)
	for i := range len {
		v := arg.Index(i).Int() // can be panic
		if v > 255 {
			panic(fmt.Errorf("arg[%v]=%v > 255", i, v))
		}
		b[i] = byte(v)
	}

	// デシリアライズ処理本体
	v, err := binary.UnmarshalRecursive(b)
	if err != nil {
		panic(err)
	}


	// JSONに変換
	u, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}

	// 空のerrorと合わせて返す
	return map[string]any{
		"val": string(u),
		"err": "",
	}
}
```

`main`関数では、グローバルオブジェクトに`binary`というオブジェクトをセットし、
その中に公開したい関数を詰め込むようにしました。
もし公開したい関数が増えたとしても衝突のリスクを軽減できます。

次に定義している`unmarshalRecursive`関数が、型変換などを担うラッパー関数です。
`js.Value`型の引数から、配列の各要素の数値を取り出して`[]byte`に詰め直しています。
実は標準ライブラリの`js.CopyBytesToGo`関数を使えばよかったことに後から気づきましたが、処理自体は同等のものです。

引数を詰め直したら`binary.UnmarshalRecursive`関数でデシリアライズし、JSONに変換して返します。
これらの処理ではエラーが発生しうるので、戻り値にはデシリアライズ結果とともにエラーも文字列として含めておき、呼び出し側でハンドリングできるようにしました。

この`main.go`を次のように`binary.wasm`にビルドし、`wasm_exec.js`と一緒にダッシュボードのソースの中にコピーして利用します。

```shell
GOOS=js GOARCH=wasm go build -o binary.wasm main.go
```

### TSコードの改修

#### GopherJS向けの実装

GopherJSの生成したJSはそのままCJSのモジュールとしてJS/TSから`require`でき、
`export`された`UnmarshalRecursive`関数をそのまま呼べるようになります。

▼リスト5: JS/TSからの利用部分の抜粋
```js
// GopherJSで生成したJSを読み込む
import binary = require("../plugins/binary.js");

...

binary.UnmarshalRecursive(room.getPublicProps_asU8());
```

生成された`binary.js`に対するTS用の型定義はリスト6のように書きます。
`UnmarshalRecursive`はデシリアライズされたオブジェクトと`error`の2つの値を返す関数なので、
2値をまとめた`Unmarshal`型を戻り値の型として定義しています。

▼リスト6: GopherJS生成JS用の型定義（binary.d.ts）
```js
declare namespace binary {
  export type Unmarshaled = [unknown, object | null];
  export function UnmarshalRecursive(src: Uint8Array): Unmarshaled;
}

export = binary;
```

#### Wasmのロード処理とラッパー関数

Wasmをロードするbinary.jsを作成し、GopherJSの場合と同様にこのファイルを`import`すれば関数を呼び出せるようにします。
これにより、`UnmarshalRecursive`関数の利用箇所の変更を最小限にできます。

▼リスト7: Wasmをロードするbinary.js
```js
import "./wasm_exec.js";
import fs from "node:fs";
import path from "node:path";

const dir = path.dirname(new URL(import.meta.url).pathname);
const go = new Go();

// 同じディレクトリにあるbinary.wasmをロード、実行する
const wasm = await WebAssembly.instantiate(
    fs.readFileSync(path.resolve(dir, "binary.wasm")), go.importObject);
go.run(wasm.instance);
const binary = globalThis.binary;

// モジュールがexportする関数。JSONの展開やエラーハンドリングも行う
export function UnmarshalRecursive(src) {
    const ret = binary.UnmarshalRecursive(src);
    if (ret.err != "") {
        return [null, ret.err]
    }
    return [JSON.parse(ret.val), null];
}
```

Goの実装でも紹介したとおり、Wasmの公開する`UnmarshalRecursive`関数はJSON文字列にしたオブジェクトとエラー文字列の組を返します。
このため、この関数を直接`export`するのではなく、JSONのデコードやエラーハンドリングをするラッパー関数を用意しました。

このラッパー関数の型はGopherJSの場合と合わせてあるので、利用側の変更を減らせます。
TS用の型定義ファイルもリスト8のように書き換えます。

▼リスト8: Wasm用の型定義（binary.d.ts）
```js
export declare type Unmarshaled = [unknown, object | null];
export function UnmarshalRecursive(src: UintArray): Unmarshaled;
```

#### インポート処理の変更

Wasm用の`binary.js`ではトップレベル`await`を使用しているため、ESM形式となります。
このため利用側のTSコードでは、CJS形式の`require`を使った`import`文からESM形式の`import`文に書き換える必要があります。
この変更のdiffをリスト9に示します。

▼リスト9: 利用側のimport文の変更
```diff
- import binary = require("../plugins/binary.js");
+ import * as binary from "../plugins/binary.js";
```

GopherJSの場合は`require`が返すモジュールオブジェクトを`binary`という名前に拘束していたので、
`binary.UnmarshalRecursive(...)`という形でデシリアライズ関数を呼び出していました。
Wasm用の`binary.js`では`UnmarshalRecursive`関数を個別に`export`しているので、
`import * as binary`のように名前空間インポートして名前を`binary`とすることで、同様の呼び出し方が可能になります。

#### ESM 対応

これまでダッシュボードのバックエンドはCJS形式で実装されていました。
しかし、モジュールシステムの節でも触れましたが、CJS形式からESM形式のモジュールをインポートするのは困難なため、
プロジェクト全体をESM形式に変更することにしました。

まずNode.jsの設定`package.json`で`"type"`を`"module"`に変更します。
TSの設定ファイル`tsconfig.json`についても、
モジュールシステムをESM形式とし、トップレベル`await`を利用しているため、
`"taraget"`と`"module"`をそれぞれ`"es2022"`、`"esnext"`に変更します。

使用しているライブラリやツールもESM対応のものに差し替える必要があります。
ダッシュボードからWSNet2のサーバーへの通信にはProtocol BuffersとgRPCを利用していますが、
コード生成ツールを`grpc_tools_node_protoc_ts`と[`protoc-gen-ts`](https://www.npmjs.com/package/grpc_tools_node_protoc_ts)から、
ESM対応の[`protoc-gen-es`](https://www.npmjs.com/package/@bufbuild/protoc-gen-es)を使うように変更しました。
またgRPCのクライアントライブラリも[`grpc-js`](https://www.npmjs.com/package/@grpc/grpc-js)から
[`connectrpc`](https://www.npmjs.com/package/@connectrpc/connect)に変更しました。
これにより、生成される型やメソッド、gRPCの呼び出し方が変わってしまうので、利用箇所を修正しました。

さらに、既存のCJS形式の`import`文を一つ一つ直していきます。
拡張子`.js`や`index.js`を省略しているところは全て省略せずに書き足します。
この修正はプロジェクトのほぼ全てのファイルに必要でした。

また`nexus-prisma`のようなCJS形式のモジュールは、リスト10の差分のように
一度全体をインポートしたあと必要なオブジェクトを取り出す形に書き換えます。

▼リスト10: nexus-prismaからのimport文の書き換え
```diff
- import { room } from "nexus-prisma";
+ import np from "nexus-prisma";
+ const { room } = np;
```

TSビルド時のエラーを手がかりに、このような修正をひたすら行いました。
これらの修正によって、無事GopherJSからWasmへの移行をすることができました。

## 成果と考察

この章では、WSNet2のダッシュボードにおいてGopherJSを使ってGoのコードを利用していた部分を、
Wasmを使う形に置き換えた実例を紹介しました。

筆者がJSやWasmについて詳しくなかったこともあり、
当初想像していたよりもかなり大掛かりな改修となってしまいました。
特にJSのモジュールシステムの違いには戸惑いましたし、
その違いに伴いライブラリの差し替えも必要だとは思いもよりませんでした。
もしかするとデシリアライザをTSで再実装するほうが早かったかもしれません。

しかしながら、TSの型チェックにもかなり助けられ、なんとか移行することができました。
やはり型システムは偉大です。
元々型を明示していなかったPHPやPythonでも最近は型を書くことが推奨されているのにも納得です。

この移行を通してGopherJSとWasmの違いに触れてきましたが、
GopherJSはWasmと比べると圧倒的に少ない労力でGoのコードをJSから利用できるものの、
やはり最新のGoへの追従の遅さには不安があります。
一方、Wasmに移行したことでGoの公式コンパイラを使ってビルドできるようになりました。
これでWSNet2サーバーの更新も滞り無く進められるようになり、当初の問題は完全に解消されました。
加えて、ダッシュボードのTSも新しいESM形式になり、モダンなライブラリにも移行できたことで、
今後の改修がやりやすくなるだろうとも感じています。

また、筆者は当初JSやTSをほとんど書いたことがなく、Wasmについて概要程度しか知らない状態でしたが、
今回の移行作業やこの記事の執筆を通してWasmの仕組みや近年の動向、
JSのモジュールシステムの歴史的経緯などを深く学ぶことができました。

WasmやESMは今まさに発展中の技術なので、今後のエコシステムのさらなる充実も期待できます。
GopherJSも便利ではありますが、長期的な視点で見るとWasmへの移行を検討する価値はあるのではないかと思います。
同じような課題に直面している方は多くはないかもしれませんが、そんな開発者の皆様の参考になれば幸いです。
