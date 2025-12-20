---
layout: post
title: "乱数はどこから来るか―TinyGo RP2040の場合"
---

<p style="background-color:lightcyan;border-left:0.3em solid cyan;padding:0.5em">
<strong>ℹ️</strong>
この記事は <a href="https://qiita.com/advent-calendar/2025/tinygo">TinyGo Advent Calendar 2025</a> 7日目の記事です。
</p>

[TinyGo Keeb Tour](https://tinygo-keeb.org/)で作成する
キーボード/マクロパッド「[zero-kb02](https://github.com/tinygo-keeb/workshop?tab=readme-ov-file#%E9%96%8B%E7%99%BA%E5%AF%BE%E8%B1%A1)」には
[RP2040](https://www.raspberrypi.com/products/rp2040/)というマイコンが載っていて、
[TinyGo](https://tinygo.org/)を使ってGo言語で書いたプログラムを動かすことができます。
このキーボードで遊べる簡単なゲームを実装している時、[`math/rand`](https://pkg.go.dev/math/rand)のグローバルな乱数が毎回固定なことに気づきました。

Go言語では1.20以降、グローバルな乱数のシードは起動時にデフォルトでランダムに設定されるので、毎回違う乱数列になるはずです。
TinyGoでは多くの標準パッケージはGo本体のものをそのまま利用していて、`math/rand`もGo本体と同じコードが使われています。

ではなぜ毎回同じ乱数列になってしまうのか、乱数はどこからやって来るのか追いかけてみました。
なお、参照しているバージョンは次の通りです。
- Go: v1.25.5
- TinyGo: v0.39.0


## `math/rand`を読む

グローバルな乱数を返す関数は何種類かありますが、内部では同じ乱数生成器（random number generator）が使われています。
たとえば`rand.Init()`は次のようになっています

▼[src/math/rand/rand.go:448-449](https://cs.opensource.google/go/go/+/go1.25.5:src/math/rand/rand.go;l=448-449)
```go
// Int returns a non-negative pseudo-random int from the default [Source].
func Int() int { return globalRand().Int() }
```

`globalRand()`は`*rand.Rand`を返す関数で、
`atomic.Pointer[Rand]`を使って1回初期化した`*Rand`が使い回されています。

▼[src/math/rand/rand.go:319-350](https://cs.opensource.google/go/go/+/refs/tags/go1.25.5:src/math/rand/rand.go;l=319-350)
```go
// globalRand returns the generator to use for the top-level convenience
// functions.
func globalRand() *Rand {
	if r := globalRandGenerator.Load(); r != nil {
		return r
	}

	// This is the first call. Initialize based on GODEBUG.
	var r *Rand
	if randautoseed.Value() == "0" {
		randautoseed.IncNonDefault()
		r = New(new(lockedSource))
		r.Seed(1)
	} else {
		r = &Rand{
			src: &runtimeSource{},
			s64: &runtimeSource{},
		}
	}

	if !globalRandGenerator.CompareAndSwap(nil, r) {
		// Two different goroutines called some top-level
		// function at the same time. While the results in
		// that case are unpredictable, if we just use r here,
		// and we are using a seed, we will most likely return
		// the same value for both calls. That doesn't seem ideal.
		// Just use the first one to get in.
		return globalRandGenerator.Load()
	}

	return r
}
```

若干長いですが、要するにこの`*Rand`が本体です。
```go
		r = &Rand{
			src: &runtimeSource{},
			s64: &runtimeSource{},
		}
```

そして、`*Rand`の`Int()`は次のようになっていて、`Rand.src.Int63()`を呼び出しています。
▼[src/rand/rand.go:95-116](https://cs.opensource.google/go/go/+/refs/tags/go1.25.5:src/math/rand/rand.go;l=95-116)
```go
// Int63 returns a non-negative pseudo-random 63-bit integer as an int64.
func (r *Rand) Int63() int64 { return r.src.Int63() }

(略)

// Int returns a non-negative pseudo-random int.
func (r *Rand) Int() int {
	u := uint(r.Int63())
	return int(u << 1 >> 1) // clear sign bit if int == int32
}
```

`Rand.src`は`runtimeSource`型で、その`Int63()`は`runtime_rand()`を呼び出しています。

▼[src/math/rand/rand.go:362-364](https://cs.opensource.google/go/go/+/refs/tags/go1.25.5:src/math/rand/rand.go;l=362-364)
```go
func (*runtimeSource) Int63() int64 {
	return int64(runtime_rand() & rngMask)
}
```

`runtime_rand()`(は次のように定義されていて、`go:linkname`で`runtime`パッケージの`rand()`が実体となっています。

▼[src/math/rand/rand.go:352-353](https://cs.opensource.google/go/go/+/refs/tags/go1.25.5:src/math/rand/rand.go;l=352-353)
```go
//go:linkname runtime_rand runtime.rand
func runtime_rand() uint64
```

TinyGoは各マイコンボード用に`runtime`を独自実装しているので、どうやら`runtime`に乱数が固定になる原因があるようです。

## TinyGoの`runtime`を読む

TinyGoの`runtime.rand()`は`algorithm.go`に定義されています。
`hardwareRand()`を呼び出してみて、`!ok`なら`fastrand64()`にフォールバックするコードになっています。

▼[tinygo/src/runtime/algorithm.go:71-81](https://github.com/tinygo-org/tinygo/blob/v0.39.0/src/runtime/algorithm.go#L70-L81)
```go
// Function that's called from various packages starting with Go 1.22.
func rand() uint64 {
	// Return a random number from hardware, falling back to software if
	// unavailable.
	n, ok := hardwareRand()
	if !ok {
		// Fallback to static random number.
		// Not great, but we can't do much better than this.
		n = fastrand64()
	}
	return n
}
```

`hardwareRand()`の定義は複数あり、ターゲットごとに設定されたビルドタグで実装が切り替わるようになっています。
zero-kb02用にビルドする時のターゲットは`waveshare-rp2040-zero`なので、`tinygo info`コマンドでビルドタグを確認します。

```shell
$ tinygo info --target=waveshare-rp2040-zero
LLVM triple:       thumbv6m-unknown-unknown-eabi
GOOS:              linux
GOARCH:            arm
build tags:        cortexm baremetal linux arm rp2040 rp waveshare_rp2040_zero tinygo purego osusergo math_big_pure_go gc.conservative scheduler.cores serial.usb
garbage collector: conservative
scheduler:         cores
```

このビルドタグに合致する`hardwareRand()`が実装されたファイルは`rand_norng.go`です。

▼[`tinygo/src/runtime/rand_norng.go`](https://github.com/tinygo-org/tinygo/blob/v0.39.0/src/runtime/rand_norng.go)
```go
//go:build baremetal && !(nrf || (stm32 && !(stm32f103 || stm32l0x1)) || (sam && atsamd51) || (sam && atsame5x) || esp32c3 || tkey || (tinygo.riscv32 && virt))

package runtime

func hardwareRand() (n uint64, ok bool) {
	return 0, false // no RNG available
}
```

ここで固定値の`0, false`が返されるので、`runtime.rand()`では`fastrand64()`にフォールバックされることになります。
`fastrand64()`は`algorithm.go`に定義されています。

▼[tinygo/src/runtime/algorithm.go:44-50](https://github.com/tinygo-org/tinygo/blob/v0.39.0/src/runtime/algorithm.go#L44-L50)
```go
// This function is used by hash/maphash.
// This function isn't required anymore since Go 1.22, so should be removed once
// that becomes the minimum requirement.
func fastrand64() uint64 {
	xorshift64State = xorshiftMult64(xorshift64State)
	return xorshift64State
}
```

Go本体では1.22以降、疑似乱数生成アルゴリズムとしてChaCha8が使われているのですが、
TinyGoはより軽量なXorshiftなんですね。

`xorshift64State`の初期値がどうなっているかというと、`hardwareRand()`を使って初期化しています。

▼[tinygo/src/runtime/algorithm.go:26-30](https://github.com/tinygo-org/tinygo/blob/v0.39.0/src/runtime/algorithm.go#L26-L30)
```go
func initRand() {
	r, _ := hardwareRand()
	xorshift64State = uint64(r | 1) // protect against 0
	xorshift32State = uint32(xorshift64State)
}
```

そうです。
ここで返された固定値`0`を使って毎回`1`が設定されるので、いつでも同じ乱数列になっていたのでした。

**12/20 追記**:
この部分間違っていました。v0.39.0までは、RP2040では`initRand()`は呼ばれていませんでした。
変数の宣言の初期値`1`がそのまま使われていいました。

## TinyGoの`crypto/rand`を読む

`math/rand`の乱数が毎回同じ乱数列になる謎は解けました。
ところで、Goの乱数生成器は`math/rand`の他に`crypto/rand`もあります。
TinyGoは`crypto`パッケージを独自に実装しているので、こちらも見てみます。

▼[tinygo/src/crypto/rand/rand.go](https://github.com/tinygo-org/tinygo/blob/v0.39.0/src/crypto/rand/rand.go)
```go
// Copyright 2010 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Package rand implements a cryptographically secure
// random number generator.
package rand

import "io"

// Reader is a global, shared instance of a cryptographically
// secure random number generator.
var Reader io.Reader

// Read is a helper function that calls Reader.Read using io.ReadFull.
// On return, n == len(b) if and only if err == nil.
func Read(b []byte) (n int, err error) {
	if Reader == nil {
		panic("no rng")
	}

	return io.ReadFull(Reader, b)
}
```

`Read()`は`crypto.Reader`から読み取るだけの実装なのですが、RP2040向けのコードではこの`Reader`を初期化するコードがありません！
このため、最初の`nil`チェックで`panic`します。


## RP2040の乱数生成器

RP2040は乱数生成器を持っていて、TinyGoからも`machine`パッケージの`GetRNG()`を通して利用できます。

▼[tinygo/src/machine/machine_rp2_rng.go:14-41](https://github.com/tinygo-org/tinygo/blob/v0.39.0/src/machine/machine_rp2_rng.go#L14-L41)
```go
// GetRNG returns 32 bits of semi-random data based on ring oscillator.
//
// Unlike some other implementations of GetRNG, these random numbers are not
// cryptographically secure and must not be used for cryptographic operations
// (nonces, etc).
func GetRNG() (uint32, error) {
	var val uint32
	for i := 0; i < 4; i++ {
		val = (val << 8) | uint32(roscRandByte())
	}
	return val, nil
}

var randomByte uint8

func roscRandByte() uint8 {
	var poly uint8
	for i := 0; i < numberOfCycles; i++ {
		if randomByte&0x80 != 0 {
			poly = 0x35
		} else {
			poly = 0
		}
		randomByte = ((randomByte << 1) | uint8(rp.ROSC.GetRANDOMBIT()) ^ poly)
		// TODO: delay a little because the random bit is a little slow
	}
	return randomByte
}
```

[RP2040のデータシート](https://pip-assets.raspberrypi.com/categories/814-rp2040/documents/RP-008371-DS-1-rp2040-datasheet.pdf?disposition=inline)にあるとおり、
ROSC（リング・オシレータ）の`RANDOMBIT`レジスタから1ビットずつ取り出す実装になっています。

今のところはこの関数を使えば、毎回異なる乱数列を取り出すことができます。
ただし、この乱数生成器は暗号論的にセキュアではないので、利用用途には注意が必要です。

## まとめ

RP2040で毎回同じ乱数列になってしまう原因を求めて、TinyGoの乱数生成器のコードを追いかけてきました。
結論として、`runtime/rand_norng.go`で定義されている`hardwareRand()`が固定値`0`を返し、それによって乱数の初期値も固定されているのが原因でした。

一方で、RP2040の持つ乱数生成器は`machine.GetRNG()`で利用可能で、毎回異なる値が取得できます。

実は`runtime/rand_hwrng.go`には、この`machine.GetRNG()`を使った`hardwareRand()`が実装されています。
なので、ビルドタグを調整するだけで`math/rand`も毎回異なる乱数列にできたりします。
これについて近々Pull Requestを出そうと思っています。

**12/20 追記**:
無事Pull Requestが取り込まれ、v0.40.1がリリースされました。
RP2040でも`hardwareRand()`が`machine.GetRNG()`を呼び出す形になりました。

## 引用ソースコードライセンス

### Go
```
Copyright 2009 The Go Authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google LLC nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### TinyGo
```
Copyright (c) 2018-2025 The TinyGo Authors. All rights reserved.

TinyGo includes portions of the Go standard library.
Copyright (c) 2009-2024 The Go Authors. All rights reserved.

TinyGo includes portions of LLVM, which is under the Apache License v2.0 with
LLVM Exceptions. See https://llvm.org/LICENSE.txt for license information.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of the copyright holder nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```


