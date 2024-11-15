---
layout: post
title: "TCP_NODELAYの効果を確かめる (KLabTechBook Vol.13)"
---

この記事は2024年5月25日から開催された[技術書典16](https://techbookfest.org/event/tbf16)にて頒布した「[KLabTechBook Vol.13](https://techbookfest.org/product/3CTYX4wj9wwBr13qJRYwA5)」に掲載したものです。

現在開催中の[技術書典17](https://techbookfest.org/event/tbf17)オンラインマーケットにて新刊「[KLabTechBook Vol.14](https://techbookfest.org/product/bZpYWjnBQDRe15rq1JdqqU)」を頒布（電子版無料、紙+電子 500円）しています。
また、既刊も在庫があるものは物理本を[オンラインマーケット](https://techbookfest.org/organization/5654456649646080)で頒布しているほか、
[KLabのブログ](https://www.klab.com/jp/blog/tech/2024/tbf17.html)からもすべての既刊のPDFを無料DLできます。
合わせてごらんください。

[<img src="/images/2024-11-03/ktbv14.jpg" width="40%" alt="KLabTechBook Vol.14" />](https://techbookfest.org/product/bZpYWjnBQDRe15rq1JdqqU)

--------

KLabでは独自のリアルタイム通信基盤「[WSNet2](https://github.com/KLab/wsnet2)」を開発運用し、OSSとしても公開しています。
ある日、WSNet2のサーバーを海外に建て、手元のクライアントからのメッセージの応答時間を調べていたところ、
想定より妙に長い時間がかかっていることに気づきました。

WSNet2はメッセージの送受信にWebSocketを利用しています[^1]。
WebSocketはHTTPをベースとしていて、基本的にはTCPでパケットを送り合うことになります。
そしてこのとき見つけた遅延の原因はTCPの機能にありました。

[^1]: WSNet2のWSはWebSocketの略です

この章では、遅延の原因となったTCPの機能である**Nagleのアルゴリズム**と`TCP_NODELAY`オプションについて解説し、
実際にどのような動きをするのか確認します。
加えて、Unity特有の事情についても解説します。

## TCPの小さなパケット問題

TCPではパケットが到達することをプロトコル自体で保証しています。
送信側はパケットのヘッダにシーケンス番号などの情報を付け加えておき、
また受信側は受信したことをACKというメッセージで送信側に通知します。
これらの情報を使って、未到達のパケットを自動で再送するようになっています。

このため、TCPでは1バイトのデータを送るだけでもTCPとIPのヘッダを合わせて40バイト以上送信することになります。
このような小さなパケットを多数送るような状況はtelnetセッションなどでよく発生し、
通信帯域の限られていた1980年代には輻輳崩壊の原因になりうるような無視できないオーバーヘッドだったようです。
この問題を回避する方法として、[RFC 896](https://datatracker.ietf.org/doc/html/rfc896)が提案されました。

## NagleのアルゴリズムとTCP_NODELAY

RFC 896で提案された手法は、送信するデータをある程度バッファリングしてひとつのTCPパケットにまとめることで効率化するというものです。
データをまとめるかどうかの決定方法は、RFCの著者の名前をとってNagleのアルゴリズムと呼ばれています。

Nagleのアルゴリズムでは、次の条件を満たすまでデータをバッファリングして、ひとつのパケットにまとめます。

 1. 未送信のデータが最大セグメントサイズ[^2]を超える
 1. 未受信のACKがなくなる

[^2]: TCPの1つのパケットに載せられる最大サイズ

2024年05月12日時点の[日本語版Wikipedia](https://ja.wikipedia.org/wiki/Nagle%E3%82%A2%E3%83%AB%E3%82%B4%E3%83%AA%E3%82%BA%E3%83%A0)では条件に「タイムアウトになる」が加えられていますが間違いです。
元のRFCにはタイマーは不要と明記されていますし[^3]、少なくともLinuxカーネルの実装にはタイムアウトはありません。

[^3]: 原文: _This inhibition is to be unconditional; no timers, tests for size of data received, or other conditions are required._

さて、WSNet2で問題になっていたのはサーバーを海外に建てているときでした。
物理的な距離によりレイテンシーが高く、ACKが届くのにも時間がかかっていました。

他にもACKが遅延する要因として、[RFC 1122](https://datatracker.ietf.org/doc/html/rfc1122)に記載されているTCP遅延ACKという機能もあります。
これはACKの返答を一時的に遅らせ、複数のACK応答をまとめて返すことでプロトコルのオーバーヘッドを減らすものです。

これらの要因でACKが遅延したために、Nagleのアルゴリズムにより、
ACKが届くまでの間に送信したメッセージはTCPのレイヤーでバッファリングされてしまいました。
このバッファリングされている時間の分、アプリケーションからは応答時間が長くなっているように見えたわけです。

このようなケースに対応するために、Nagleのアルゴリズムを無効にするオプション`TCP_NODELAY`が用意されており、`setsockopt`関数で設定できます。

## 実験

それでは実際にNagleのアルゴリズムの働きと`TCP_NODELAY`の効果を確認してみましょう。

### TCPサーバーとネットワーク遅延設定

まずはDockerを使って単純なTCPサーバーとネットワーク遅延環境を用意します。
DockerはLinuxなので、tcコマンド（traffic control）で通信遅延のエミュレートが簡単にできます。

最初にTCPサーバー用のコンテナを立ち上げます。
ネットワーク遅延を設定するためには、`--privileged`オプションの指定が必要です[^4]。
また、名前を`tcpsv`としておきます。

[^4]: userns-remapを設定している場合は`--userns=host`の指定も必要です。userns-remapについてはKLabTechBook Vol.11「[Dockerを使うなら当然userns-remapしてるよね！]({% post_url 2024-06-08-klabtechbook11-docker-userns-remap %})」をご覧ください。

```shell
docker run -it --name=tcpsv --privileged alpine
```

コンテナが起動したら`tc`コマンドをインストールし、送信パケットを1秒遅延させるように設定します。
`tc`コマンドで指定するデバイス`eth0`は外部との通信に使われるネットワークインターフェイスです。
このコンテナから外部へ送信するパケットは遅延しますが、受信するものは遅延しないことに注意してください。

```shell
apk add iproute2-tc
tc qdisc add dev eth0 root netem delay 1s
```

TCPサーバーは`nc`コマンド（netcat）を使うことで簡単に用意できます。
次のように5000番ポートで待ち受けます。

```shell
nc -l -p 5000
```

### クライアントの実装

指定サーバーにTCPで1文字ずつ送るプログラムを用意しました。
このソースコードは[GitHub Gistにも置いてある](https://gist.github.com/makiuchi-d/f748ca25bd4089756faa45fe3af4ced0/raw/main.c)のでダウンロードしてお使いください。

▼リスト1 main.c
```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>
#include <sys/socket.h>
#include <netinet/tcp.h>

int main(int argc, char **argv)
{
	if (argc <= 2) {
		printf("usage: %s <host> <port> [nodelay]\n", argv[0]);
		return 0;
	}

	struct addrinfo hint, *addr;
	memset(&hint, 0, sizeof(hint));
	hint.ai_family = AF_INET;
	hint.ai_socktype = SOCK_STREAM;
	if (getaddrinfo(argv[1], argv[2], &hint, &addr) != 0) {
		perror("getaddrinfo");
		return 1;
	}

	int sock = socket(
		addr->ai_family, addr->ai_socktype, addr->ai_protocol);
	if (sock == -1) {
		perror("socket");
		return 1;
	}

	/* TCP_NODELAYの設定 */
	int n = (argc > 3) ? atoi(argv[3]) : 0;
	if (setsockopt(sock, SOL_TCP, TCP_NODELAY, &n, sizeof(n)) == -1) {
		perror("setsockopt");
		return 1;
	}

	if (connect(sock, addr->ai_addr, addr->ai_addrlen) == -1) {
		perror("connect");
		return 1;
	}

	/* 1文字ずつ100ms間隔で送信 */
	for (int i=0; i<100; i++) {
		char c = '0' + (i % 10);
		write(sock, &c, 1);
		usleep(100000);
	}

	close(sock);
	freeaddrinfo(addr);

	return 0;
}
```

クライアント用のコンテナを立ち上げ、`gcc`でコンパイルします。
サーバーコンテナ`tcpsv`にアクセスしやすいよう`--link`も指定しておきます。

```shell
docker run -it --link=tcpsv alpine

apk add gcc libc-dev
wget https://gist.github.com/makiuchi-d/f748ca25bd4089756faa45fe3af4ced0/raw/main.c
gcc -o tcpcl main.c
```

ビルドした`tcpcl`コマンドは引数でサーバーとポートを指定して実行します。
サーバーコンテナには`tcpsv`という名前でアクセスできます。

```shell
./tcpcl tcpsv 5000
```

サーバーコンテナの画面に0~9の数字が順に表示されることが確認できるはずです。
クライアントが終了すると`nc`も停止するので、サーバーコンテナ側で毎回`nc`コマンドを実行しなおしてください[^5]。

[^5]: ncを終了するためにサーバーコンテナ側で何度かエンターキーを入力する必要があることがあります

### 通信内容の確認

LinuxマシンでDockerを使っている場合は簡単です。
ホストの`docker0`インターフェイスを[Wireshark](https://www.wireshark.org/)などでキャプチャすることでコンテナ間の通信内容を見ることができます。

`tcpcl`実行時の通信内容は図1のようになっています。

![Nagleのアルゴリズムの効果](/images/2024-11-16/cap-nagle.png)
▲図1 Nagleのアルゴリズムの効果

サーバーからのACKを受け取ってからデータを送信していて、Data部が`"0123456789"`の10文字になっているのがわかります。
また実行中にサーバーの画面をみていると、約10文字ごとに表示が進んでいくのが見て取れると思います。

続いて`TCP_NODELAY`を有効にしてみます。
`tcpcl`の3番目の引数に`1`を指定すると有効になります。

```shell
./tcpcl tcpsv 5000 1
```

図2のように、サーバーからのACKを待たずに1文字ずつ送信しているのが見て取れます。
サーバーの画面も1文字ずつ順に表示が進んでいくことが分かるはずです。

![TCP_NODELAYの効果](/images/2024-11-16/cap-nodelay.png)
▲図2 `TCP_NODELAY`の効果

このように、Nagleのアルゴリズムによって1パケットにデータがまとめられている様子や、
`TCP_NODELAY`によってそれが無効になっている様子が確認できました。

## Unity特有の事情

C#では`Socket`クラスの`NoDelay`プロパティによって`TCP_NODELAY`の有効無効を設定できます。
このプロパティをセットすると、内部では最終的に`setsockopt`関数がよばれます。

WSNet2のC#クライアント実装では、標準ライブラリの`System.Net.WebSockets.ClientWebSocket`を使用しています。
現在公式サポートされているUnityの[C#ランタイムは.NET Framework 4.8相当](https://docs.unity3d.com/ja/2023.2/Manual/dotnetProfileSupport.html)で、
とても残念なことに、WebSocket接続時の`NoDelay`は`false`になっています。
このために、冒頭で言及した応答時間調査のときにはNagleのアルゴリズムが有効になっていて余計な遅延が発生していました。

さらに酷いことに、`ClientWebSocket`クラスには内部の`Socket`にアクセスする手段がありません。
仕方がないので、WSNet2ではUnityの場合にはリフレクションを使って`Socket`を取り出し、`NoDelay`プロパティを[設定するようにしました](https://github.com/KLab/wsnet2/blob/v0.6.1/wsnet2-unity/Assets/WSNet2/Scripts/Core/Connection.cs#L476-L521)。

.NET 5以降では、依然として`ClientWebSocket`から`NoDelay`を設定するインターフェイスは存在しないものの、
WebSocket接続時に`NoDelay`は`true`に設定されるので、Nagleのアルゴリズムによる遅延の心配はありません。

## まとめ

ここまで、Nagleのアルゴリズムと`TCP_NODELAY`オプションについて解説し、実際の動作を確認しました。
ゲームの協力プレイやオンライン対戦では、パケットをまとめることによる帯域の節約よりもリアルタイム性のほうが大切です。
このようなケースでは`TCP_NODELAY`を設定したほうがよいでしょう。
また、想定以上の遅延が見られたときは`TCP_NODELAY`が設定されているか確認してみてください。
