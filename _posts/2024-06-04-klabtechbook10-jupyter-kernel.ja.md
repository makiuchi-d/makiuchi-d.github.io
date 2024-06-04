---
layout: post
title: "Jupyterカーネル自作入門 (KLabTechBook Vol.10)"
---

この記事は2022年9月10日から開催された[技術書典13](https://techbookfest.org/event/tbf13)にて頒布した「[KLabTechBook Vol.10](https://techbookfest.org/product/7NsztMZryqYKS6FEaW9QCK)」に掲載したものです。
**Whitespaceのコードをそのまま紙面に載せました**。

現在開催中の[技術書典16](https://techbookfest.org/event/tbf16)オンラインマーケットにて新刊「[KLabTechBook Vol.13](https://techbookfest.org/product/3CTYX4wj9wwBr13qJRYwA5)」を頒布（電子版無料、紙+電子 500円）しています。
また、既刊も在庫があるものは物理本を[オンラインマーケット](https://techbookfest.org/organization/5654456649646080)で頒布しているほか、
[KLabのブログ](https://www.klab.com/jp/blog/tech/2024/tbf16.html)からもすべての既刊のPDFを無料DLできます。
合わせてごらんください。

[<img src="/images/2024-05-29/ktbv13.jpg" width="40%" alt="KLabTechBook Vol.13" />](https://techbookfest.org/product/3CTYX4wj9wwBr13qJRYwA5)

--------

Jupyter Lab（あるいはJupyter Notebook）[^1]は、ブラウザ上でプログラムを記述し実行できるウェブアプリケーションです。
プログラムと一緒に説明や実行時の入出力を**ノートブック**という形式でまとめて保存でき、実験の記録などに便利なツールです。
機械学習やデータ分析でよく使われているので、ご存知の方も多いと思います。

Project Jupyterは元々はPythonのインタラクティブインタプリタIPythonの派生プロジェクトですが、
プログラムの実行環境が**カーネル**として分離されているため、現在ではPython以外にもコミュニティによるものも含め数十の言語がサポートされています。

この章では、このJupyterに新たな言語のカーネルを自作して追加する方法を解説します。
題材として、**Whitespace**[^2]を実行するカーネルをGo言語で実装した「whitenote」を用意しました。
紙面の都合上抜粋しての解説となりますので、実際に動かしたりコードの全体を見たい場合はリポジトリをご覧ください。

* [https://github.com/makiuchi-d/whitenote](https://github.com/makiuchi-d/whitenote)

また、筆者の開発環境は次のとおりです。

* Ubuntu 20.04
* Jupyter Lab 3.4.4
* Go 1.19

![whitenote](/images/2024-06-04/jupyter.gif)
▲図1 whitenote

[^1]: [https://jupyter.org/](https://jupyter.org/)
[^2]: [https://web.archive.org/web/20150618184706/http://compsoc.dur.ac.uk/whitespace/](https://web.archive.org/web/20150618184706/http://compsoc.dur.ac.uk/whitespace/)

## Jupyterカーネルの基本

JupyterのカーネルはJupyterから起動される独立したプログラムで、
基本的には1ノートブックに対し1プロセスが起動されます。
Jupyterとの通信には**ZeroMQ**[^3]というライブラリを利用します。
このため、ZeroMQが利用できるものであれば、どんな言語でもカーネルを開発できます。

公式のドキュメントにもカーネルの作り方の解説があります[^4]。
Pythonで実装する場合は`ipykernel.kernelbase.Kernel`を拡張することで簡単に実装できますが、
ここでは他言語でも真似できるよう、ZeroMQを直接操作する方法を紹介します。

[^3]: [https://zeromq.org/](https://zeromq.org/)
[^4]: [https://jupyter-client.readthedocs.io/en/latest/kernels.html](https://jupyter-client.readthedocs.io/en/latest/kernels.html)

### ZeroMQとは

Jupyterが利用するZeroMQは、軽量な非同期メッセージングライブラリです。
ZeroMQ自体はC++で開発されていますが、多くの言語で利用できるようにライブラリとバインディングが用意されていて[^5]、
相互に通信できるようになっています。

[^5]: [https://zeromq.org/get-started/#pick-your-language](https://zeromq.org/get-started/#pick-your-language)

ZeroMQではインターフェイスとして、TCPなどのソケットをラップしたような使い勝手の**ソケット**が提供されます。
このソケットにはさまざまなタイプ、たとえばメッセージを分配したり、ルーティングを自動で行ってくれるものなどが用意されています。
これらを組み合わせることで、Pub/Subや分散タスク処理のようなN対Nの通信を柔軟に組み立てることができます。

Go言語でZeroMQを利用するにはいくつかの選択肢があります。
公式サイトで紹介されている、goczmq[^6]、pubbe/zmq4[^7]のほか、
Go言語のみで再実装されたgo-zeromq/zmq4[^8]などがあります。

[^6]: [https://github.com/zeromq/goczmq](https://github.com/zeromq/goczmq)
[^7]: [https://github.com/pebbe/zmq4](https://github.com/pebbe/zmq4)
[^8]: [https://github.com/go-zeromq/zmq4](https://github.com/go-zeromq/zmq4)

ここでは、他言語でも利用できる**libzmq**をシンプルにラップしているpubbe/zmq4を使うことにしました。
Ubuntu（focal, jammy）やDebian（bullseye）では次のコマンドでlibzmqをインストールできます。

```
apt install libzmq3-dev libzmq5
```

### 通信に使うソケット

Jupyterのカーネルは、表1の5つのソケットを使用します。

▼表1 ソケット一覧

名前|タイプ|役割
---|---|---
Shell|ROUTER|コードの実行や各種情報のリクエストを受け付ける
IOPub|PUB|標準出力や状態をJupyterに通知する
Stdin|ROUTER|標準入力への入力をJupyterにリクエストし受け取る
Control|ROUTER|Shellと並行しての情報の取得や、終了リクエストを受け付ける
HB|REP|疎通確認（HeartBeat）の送受信を行う

コードの実行のようなJupyterからのリクエストは、**Shellソケット**に届きます。
つまりカーネルの基本動作はShellソケットに届いたリクエストを順次処理していくことです。
その過程で入出力があれば、IOPubやStdinのソケットを使って通信します。

Jupyterとカーネルの通信は基本的に1対1ですが、複数のリクエストを並行して送受信できるようにROUTERタイプのソケットが使われています。

### メッセージの基本構造

メッセージの構造は公式ドキュメントでも解説されているのですが[^9]、
libzmqを直接使って実装するには説明が不十分なので注意が必要です[^10]。

[^9]: [https://jupyter-client.readthedocs.io/en/latest/messaging.html](https://jupyter-client.readthedocs.io/en/latest/messaging.html)
[^10]: Pythonで実装する場合はライブラリが隠蔽しているのでしっかりとは書いていないのでしょう。

さっそくドキュメントには書かれていないのですが、Jupyterとの通信はZeroMQのマルチパートメッセージで行います。
これは、複数のブロックをまとめてひとつのメッセージとして扱うものです。

pubbe/zmq4では、`RecvMessageBytes()`と`SendMessage()`を利用します。
libzmqのAPIとしては、送受信時に`ZMQ_SNDMORE`、`ZMQ_RCVMORE`を使うことになります[^11]。

[^11]: [http://api.zeromq.org/master:zmq-send](http://api.zeromq.org/master:zmq-send)、[http://api.zeromq.org/master:zmq-recv](http://api.zeromq.org/master:zmq-recv)

▼リスト1 マルチパートメッセージの送受信関数
```go
func (*zmq4.Socket) RecvMessageBytes(flags zmq4.Flag) (msg [][]byte, err error)
func (*zmq4.Socket) SendMessage(parts ...interface{}) (total int, err error)
```

メッセージの内容は表2に示すブロックの列になっています。
このうち`{header}`、`{parent_header}`、`{metadata}`、`{content}`はそれぞれ
JSONエンコードされた辞書データです。

▼表2 メッセージの内容

ブロック|内容
---|---
`"<IDS|MSG>"`|メッセージの先頭を表すデリミタ文字列
HMAC|検証のためのシグネチャ（16進数文字列）
`{header}`|メッセージの種別を表すヘッダ
`{parent_header}`|親メッセージのヘッダ（ない場合は"`{}`"）
`{metadata}`|メタデータ
`{content}`|メッセージのコンテンツ
...|追加データがある場合はブロックが続く

ROUTERタイプのソケットで通信する場合、メッセージ本体の前にZeroMQが利用するID（ZmqID）が付加されます。
ZeroMQでよくあるソケットの組み合わせ、たとえばROUTER-DEALERパターンなどでは、
このZmqIDはソケットが自動的に付け外ししてくれるので意識する必要はありません。
しかしROUTERソケットを直接扱う場合、
つまりShell、Stdin、Controlのソケットの処理では、このZmqIDを適切に操作しなくてはなりません。

ROUTERの詳細はZeroMQのガイドブック[^12]に書かれているので、興味のある方は参照ください。

[^12]: [https://zguide.zeromq.org/](https://zguide.zeromq.org/) 日本語訳:[https://www.cuspy.org/diary/2015-05-07-zmq/](https://www.cuspy.org/diary/2015-05-07-zmq/)

## 最小のカーネル

カーネルとして最低限必要なのは次の4つです。

* 起動してもらえるようカーネルを登録する
* 通信に使うソケットを準備する
* `kernel_info_request`に応答する
* HeartBeatに応答する

### カーネルの登録

カーネルはJupyterとは独立したプログラムなので、まずはJupyterに起動してもらえるよう登録します。
具体的には、特定のディレクトリに`kernel.json`ファイルを配置することで登録します。
このファイルには、カーネルのコマンドやパラメータを記載します（リスト2）。
詳細は公式ドキュメントをご覧ください[^13]。

[^13]: [https://jupyter-client.readthedocs.io/en/stable/kernels.html#kernelspecs](https://jupyter-client.readthedocs.io/en/stable/kernels.html#kernelspecs)

▼リスト2 kernel.json
```json
{
    "argv": [
        "whitenote",
        "{connection_file}"
    ],
    "display_name": "Whitespace",
    "language": "whitespace"
}
```

`"argv"`がカーネルのコマンドとパラメータです。
`"{connection_file}"`は、後述する通信のための情報が書かれたファイルのパスに置き換えられます。
他に必要なパラメータがある場合ここに追加します。
`"display_name"`がJupyter上に表示される名前です。
Jupyterでカーネルが選択されると、この指定にしたがってコマンドが起動されます。

ロゴ画像を設定するには`logo-64x64.png`というPNGファイルを同じディレクトリに配置します[^14]。
画像がなくても名前の頭文字がロゴ画像として使われるので、必須ではありません。

[^14]: `logo-32x32.png`は使われていません。[https://github.com/ipython/ipython/pull/6537](https://github.com/ipython/ipython/pull/6537)

ファイルを用意したら次のコマンドで配置します。
OSによって異なりますが、Linuxでは`~/.local/share/jupyter/kernels`に
`--name`で指定した名前のディレクトリが作られ、コピーされます。

```
jupyter kernelspec install --name=whitenote --user {kernel.jsonのディレクトリ}
```

正しく登録されているかは、Jupyterの画面や次のコマンドで確認できます。

```
jupyter kernelspec list
```

### ソケットの準備

通信に使うソケットの接続情報は、起動パラメータで指定される`"{connection_file}"`という名のJSONファイルで渡されます。
これにはソケットの接続プロトコル、ポート番号、IPアドレス、そしてメッセージの署名に使うアルゴリズムとキーが含まれます。

▼リスト3 connection_fileの内容
```json
{
  "shell_port": 49835,
  "iopub_port": 53257,
  "stdin_port": 34911,
  "control_port": 42447,
  "hb_port": 55339,
  "ip": "127.0.0.1",
  "key": "ef710209-2e9d78e0f61f5ec628d0c840",
  "transport": "tcp",
  "signature_scheme": "hmac-sha256",
  "kernel_name": "whitenote"
}
```

単純なJSONファイルなので、Go言語では標準ライブラリで読み取ることができます。
whitenoteではリスト4の構造体にマッピングしています。

▼リスト4 ConnectionInfo構造体
```go
type ConnectionInfo struct {
    SignatureScheme string `json:"signature_scheme"`
    Transport       string `json:"transport"`
    StdinPort       int    `json:"stdin_port"`
    ControlPort     int    `json:"control_port"`
    IOPubPort       int    `json:"iopub_port"`
    HBPort          int    `json:"hb_port"`
    ShellPort       int    `json:"shell_port"`
    Key             string `json:"key"`
    IP              string `json:"ip"`
}
```

この情報を元にJupyterとの通信に使うソケットを作り、ポートに紐づけるコードをリスト5に示します。
5つのソケットは`Sockets`構造体にまとめました。

▼リスト5 ソケットの準備
```go
type Sockets struct {
    conf    *ConnectionInfo
    shell   *zmq4.Socket
    control *zmq4.Socket
    stdin   *zmq4.Socket
    iopub   *zmq4.Socket
    hb      *zmq4.Socket
}

func bindSocket(typ zmq4.Type, transport, ip string, port int) *zmq4.Socket {
    sock, err := zmq4.NewSocket(typ)
    if err != nil {
        panic(err)
    }
    sock.Bind(fmt.Sprintf("%s://%s:%d", transport, ip, port))
    return sock
}

func newSockets(conf *ConnectionInfo) *Sockets {
    return &Sockets{
        conf:    conf,
        shell:   bindSocket(zmq4.ROUTER, conf.Transport, conf.IP, conf.ShellPort),
        control: bindSocket(zmq4.ROUTER, conf.Transport, conf.IP, conf.ControlPort),
        stdin:   bindSocket(zmq4.ROUTER, conf.Transport, conf.IP, conf.StdinPort),
        iopub:   bindSocket(zmq4.PUB, conf.Transport, conf.IP, conf.IOPubPort),
        hb:      bindSocket(zmq4.REP, conf.Transport, conf.IP, conf.HBPort),
    }
}

func main() {
    ... (略)

    socks := new Sockets(conf)

    go socks.shellHandler()
    go socks.controlHanlder()
    go socks.hbHandler()

    ... (略)
```

これらのソケットはすべて、カーネル側でBindしてJupyterからの接続を待ち受ける形をとります。
実際の接続処理はZeroMQがバックグラウンドで行ってくれます。
あとは待っていればJupyter側からメッセージを送ってくるので、それをハンドラ関数で処理していくことになります。

### Shellハンドラの実装

カーネルに接続したJupyterは、最初にShellソケットに`kernel_info_request`を送ってきます。
最小のカーネルでも、このリクエストにだけは応答しなければなりません。

このリクエストに対してカーネルは`kernel_info_reply`を返し、IOPub経由で状態を`"idle"`として通知します。
また、Controlソケットにも`kernel_info_request`が送られてきますが、Shellソケットで応答するので、そちらは読み捨てます。

ここではまず、リスト6にShellのハンドラメソッド`shellHandler`を示し、
その内容について詳しく説明していきます。

▼リスト6 Shellのハンドラメソッド
```go
func (s *Sockets) shellHandler() {
    for {
        // メッセージの受信
        msg, err := s.recvRouterMessage(s.shell)
        if err != nil {
            log.Printf("shell: recv: %v", err)
            continue
        }

        // headerのデコード
        var hdr map[string]any
        if err := json.Unmarshal(msg.Header, &hdr); err != nil {
            log.Printf("shell: header: %v", err)
            continue
        }

        // メッセージ種別ごとの処理
        switch hdr["msg_type"] {

        case "kernel_info_request":
            // kernel_info_replyの送信
            s.sendRouter(s.shell, msg, "kernel_info_reply", kernelInfo)

            // 状態を"idle"に
            s.sendState(msg, stateIdle)
        }
    }
}
```

### メッセージの受信

メッセージを受信する関数をリスト7に示します。
ShellはROUTERなので、先頭にZmqIDが付加されます。
ROUTERが多段になっている場合、ZmqIDが複数ブロックになっていることもあります。
ZmqIDとメッセージの区切りは、デリミタ文字列`"<IDS|MSG>"`のブロックによって識別します。

▼リスト7 ROUTERソケットからのMessage読み込み
```go
const delimiter = "<IDS|MSG>"

type Message struct {
    ZmqID    [][]byte
    Header   []byte
    Parent   []byte
    Metadata []byte
    Content  []byte
    Buffers  [][]byte
}

func (s *Sockets) recvRouterMessage(sock *zmq4.Socket) (*Message, error) {
    mb, err := sock.RecvMessageBytes(0)
    if err != nil {
        return nil, err
    }

    // デリミタを探す
    var d int
    for d = 0; d < len(mb); d++ {
        if bytes.Equal(mb[d], []byte(delimiter)) {
            break
        }
    }
    if d > len(mb)-5 {
        return nil, fmt.Errorf("invalid message: %v,%v, %v", d, len(mb), mb)
    }

    msg := &Message{
        ZmqID:    mb[:d],
        Header:   mb[d+2],
        Parent:   mb[d+3],
        Metadata: mb[d+4],
        Content:  mb[d+5],
        Buffers:  mb[d+6:],
    }

    // シグネチャの検証
    sig := string(mb[d+1])
    mac := calcHMAC(s.conf.Key, msg.Header, msg.Parent, msg.Metadata, msg.Content)
    if sig != mac {
        return msg, fmt.Errorf("invalid hmac: %v %v", sig, mb)
    }

    return msg, nil
}
```

#### シグネチャの検証

デリミタの次のブロックは、メッセージの検証のためのシグネチャです。
受信時の検証をスキップしたり、送信時もシグネチャを空文字列とすることで検証を無効にもできますが、簡単なので実装してしまいます。

アルゴリズムは`ConnectionInfo`の`"signature_scheme"`で指定されますが、いまのところSHA256のHAMC固定です。
また、HMACのキーも`ConnectionInfo`の`"key"`として渡されます。
このキーを使い、受信したメッセージの`{header}`、`{parent_header}`、`{metadata}`、`{content}`を
この順に連結したもののハッシュを計算し検証します。
追加データ（`Buffers`）はここに含みません。

▼リスト8 HMACの計算
```go
func calcHMAC(key string, header, parent, metadata, content []byte) string {
    h := hmac.New(sha256.New, []byte(key))
    h.Write(header)
    h.Write(parent)
    h.Write(metadata)
    h.Write(content)
    return hex.EncodeToString(h.Sum(nil))
}
```

#### メッセージの種別

メッセージの`{header}`はリスト9のようなJSONオブジェクトです。
`shellHandler`では辞書`map[string]any`としてデコードしています。

▼リスト9 メッセージの`{header}`
```json
{
  "date": "2022-08-13T06:32:13.893Z",
  "msg_id": "c1735592-e938-4d8a-b7a2-769d795f65d0",
  "msg_type": "kernel_info_request",
  "session": "aa3af91f-a747-42c7-b0b8-a02179aee1e1",
  "username": "",
  "version": "5.2"
}
```

ここで必要なのは、メッセージ種別を表す`"msg_type"`だけです。
カーネルが処理しないメッセージは単に読み捨てるだけでよいので、
ここでは`"kernel_info_request"`のメッセージのみ処理します。

#### `kernel_info_reply`の送信

`"kernel_info_request"`に対しては、`"kernel_info_reply"`という`msg_type`のメッセージを返します。
このときメッセージの`{content}`はリスト10のようにカーネルの情報をまとめたJSONオブジェクトです。
これに`{header}`などを合わせてメッセージを組み立て送信します。
このカーネル情報は基本的に固定値なので、`init()`で初期化して保持しています。

また、後で必要となる`sessionId`と、基本的に空のままの`metadata`も
起動中変更されることはないので、同じようにグローバルに保持することにします。

▼リスト10 固定値の初期化
```go
var (
    sessionId  string // プロセスごとにユニークなID
    kernelInfo []byte // カーネル情報

    metadata  = []byte("{}")
)

func init() {
    sid, _ := uuid.NewRandom()
    sessionId = sid.String()

    kernelInfo, _ = json.Marshal(map[string]any{
        "status":                 "ok",
        "protocol_version":       "5.3",
        "implementation":         "whitenote",
        "implementation_version": "0.1",
        "language_info": map[string]any{
            "name":               "whitespace",
            "version":            "0.1",
            "mimetype":           "text/x-whitespace",
            "file_extension":     ".ws",
            "pygments_lexer":     "",
            "codemirror_mode":    "",
            "nbconvert_exporter": "",
        },
        "banner": "",
    })
}
```

次に、ヘッダを構築する関数はリスト11のようにしました。
`msg_type`だけ指定すれば構築できるようにしてあります。

▼リスト11 ヘッダ構築関数
```go
func newHeader(msgtype string) []byte {
    mid, _ := uuid.NewRandom()
    h := map[string]any{
        "date":     time.Now().Format(time.RFC3339), // 現在時刻
        "msg_id":   mid.String(), // メッセージ毎にユニークなUUID
        "username": "kernel",
        "session":  sessionId,    // プロセスごとにユニークなUUID
        "msg_type": msgtype,
        "version":  "5.3",
    }
    hdr, _ := json.Marshal(h)
    return hdr
}
```

ShellソケットはROUTERなので、送信するときにはZmqIDがメッセージの先頭に必要です。
ここでは親メッセージ、`"kernel_info_request"`の`ZmqID`をそのまま使います。
また、`{parent_header}`も親メッセージの`{header}`です。

これで返信に必要な情報が揃いました。

* `ZmqID` : 親メッセージの`ZmqID`
* HMAC : `calcHMAC()`で計算
* `{header}` : `msg_type`を`"kernel_info_reply"`として構築
* `{parent_header}` : 親メッセージの`{header}`
* `{metadata}` : `{}`
* `{content}` : カーネル情報 `kernelInfo`

これらを順番どおりに結合してソケットの`SendMessage()`で送信します。
この処理を`sendRouter()`メソッドとしてまとめました（リスト12）。

▼リスト12 sendRouterメソッド
```go
func (s *Sockets) sendRouter(
    sock *zmq4.Socket, parent *Message, msgtype string, content []byte) {

    hdr := newHeader(msgtype)
    phdr := parent.Header
    mac := calcHMAC(s.conf.Key, hdr, phdr, metadata, content)
    data := make([]any, 0, len(parent.ZmqID)+6)
    for _, p := range parent.ZmqID {
        data = append(data, p)
    }
    data = append(data, delimiter)   // "<IDS|IMG>"
    data = append(data, mac)         // HMAC
    data = append(data, hdr)         // {header}
    data = append(data, phdr)        // {parent_header}
    data = append(data, metadata)    // {metadata}
    data = append(data, content)     // {content}
    _, _ = sock.SendMessage(data...)
}
```

#### 状態の通知

`"kernel_info_reply"`を返した後、カーネルはコードの実行準備が整ったことをJupyterに伝えます。
これはIOPubソケットに対して`"idle"`状態を通知することで行います。
この状態通知メソッドを`sendState()`としてリスト13のように定義しました。

▼リスト13 stateの送信
```go
var (
    stateIdle = []byte(`{"execution_state":"idle"}`)
    stateBusy = []byte(`{"execution_state":"busy"}`)
)

func (s *Sockets) send(sock *zmq4.Socket, parent *Message, msgtype string, content []byte) {
    hdr := newHeader(msgtype)
    phdr := parent.Header
    mac := calcHMAC(s.conf.Key, hdr, phdr, metadata, content)
    _, _ = sock.SendMessage(delimiter, mac, hdr, phdr, metadata, content)
}

func (s *Sockets) sendState(parent *Message, state []byte) {
    s.send(s.iopub, parent, "status", state)
}
```

`{content}`は`{"execution_state":"idle"}`とします。
このバイト列は不変でかつ何度も使うことになるので、`"busy"`のものと合わせてグローバルに保持しました。
`{header}`は`msg_type`を`"status"`とし、
`{parent_header}`は`"kernel_info_request"`のものにします。

IOPubは`PUB`ソケットなので、ZmqIDは必要ありません。
デリミタ（`"<IDS|MSG>"`）から順にマルチパートメッセージを送ります。

ここまで実装したら、Jupyterはカーネルをきちんと起動できるようになります。
`"kernel_info_reply"`を正しく返せなかったり、`"idle"`状態にできなかったりすると、
Jupyterはしつこく`"kernel_info_request"`を何度も送ってきます。
もしそのような挙動になったら、今一度実装を見直してみてください。

### ControlとHB（HeartBeat）のハンドラ

Controlソケットには`"kernel_info_request"`のほか、いくつかのリクエストが届きます。
Jupyterのカーネルでは、処理しないリクエストは単に読み捨てることになっています。
また、シャットダウン要求`"shutdown_request"`も届きますが、
これを無視してもJupyterからはSIGINTが送られてくるので、シグナルハンドラを変更していないなら自動的に終了してくれます。
ということで、Controlのハンドラはリスト14のように、すべて読み捨てるだけの実装としました。

▼リスト14 Controlハンドラの実装
```go
func (s *Sockets) controlHandler() {
    for {
        _, _ = s.recvRouterMessage(s.control)
    }
}
```

HBソケットには疎通確認のメッセージが届きます。
このメッセージはそのままHBソケットで送り返すことで疎通していることを伝えます。

メッセージをひとつひとつ`Recv()`、`Send()`するループを書いてもよいのですが、
ZeroMQの組み込みProxyを使うこともできます（リスト15）。

▼リスト15 組み込みProxyによるHBHandler
```go
func (s *Sockets) hbHandler() {
    zmq4.Proxy(s.hb, s.hb, nil)
}
```

これで最小の何もしないカーネルが実装できました。
コードの実行要求`"execute_request"`に対して何もしていないので、
Jupyter上で実行ボタンを押してもなにも起こりませんが、通信はできています。

## Whitespaceとは

ここからは、Jupyterに新たな言語としてWhitespaceのカーネルを実際に組み込んでみます。
Whitespaceを選択したのは、実装が簡単なことに加え、調べた限り誰も作っていなさそう[^15]だったからです。

[^15]: ググラビリティが低いため、見つけられていないだけかもしれません。

Whitespaceは難解プログラミング言語のひとつで、2003年4月1日にEdwin BradyとChris Morrisによって開発、発表されました。
公式サイトはすでに消滅していますが、Internet Archiveで見ることができます。

この言語の特徴はなんといっても、スペース、タブ、改行という空白文字3種のみで記述することです。
それ以外の文字は全て無視されます。
リスト16に「`Hello!`」と表示するプログラムを示します[^16]。

[^16]: 可視化するとこうなります: SSSTSSTSSSNTNSSSSSTTSSTSTNTNSSSSSTTSTTSSNSNSTNSSTNSSSSSTTSTTTTNTNSSSSSTSSSSTNTNSSNNN

▼リスト16 `Hello!`と表示するプログラム
```whitespace
   	  	   
	
     		  	 	
	
     		 		  
 
 	
  	
     		 				
	
     	    	
	
  


```

Whitespaceはヒープメモリを備えたスタックベースの言語で、表3の命令セットで構成されます。
便宜上、スペースをS、タブをT、改行をNとして表記します。
詳細は公式サイトのチュートリアル[^17]をご覧ください。

▼表3 Whitespaceの命令セット

命令|引数|意味
---|---|---
SS|数値|数値をスタック先頭にPush
SNS| |スタック先頭のアイテムを複製
STS|数値|スタックのN番目のアイテムを先頭にコピー
SNT| |スタック先頭の2つを入れ替え
SNN| |スタック先頭のアイテムを破棄
STN|数値|先頭のアイテムを保持したままN個のアイテムを破棄
TSSS| |加算
TSST| |減算
TSSN| |乗算
TSTS| |除算
TSTT| |剰余
TTS| |先頭アイテムを2番目の示すアドレスのヒープに保存
TTT| |先頭の示すアドレスのヒープから値をスタックに取り出す
NSS|ラベル|ラベルを設置
NST|ラベル|サブルーチン呼び出し
NSN|ラベル|ラベルへジャンプ
NTS|ラベル|スタック先頭が0ならラベルへジャンプ
NTT|ラベル|スタック先頭が負ならラベルへジャンプ
NTN| |サブルーチン呼び出し元へ戻る
NNN| |プログラム終了
TNSS| |スタック先頭を文字として出力
TNST| |スタック先頭を数値として出力
TNTS| |入力から1文字読み、スタック先頭の示すヒープに保存
TNTT| |入力から数値を読み、スタック先頭の示すヒープに保存

[^17]: [https://web.archive.org/web/20150618184706/http://compsoc.dur.ac.uk/whitespace/tutorial.php](https://web.archive.org/web/20150618184706/http://compsoc.dur.ac.uk/whitespace/tutorial.php)

## インタプリタの実装

whitenoteのwspaceパッケージ[^18]にWhitespaceインタプリタを実装しました。
実装の詳細はリポジトリを見ていただくとして、ここではインタプリタの本体である`wspace.VM`の使い方を簡単に紹介します。

[^18]: [https://github.com/makiuchi-d/whitenote/tree/main/wspace](https://github.com/makiuchi-d/whitenote/tree/main/wspace)

▼リスト17 `wspace.VM`の使い方
```go
vm := wspace.New()

err := vm.Load([]byte("   \t\t \t\n\t\n \t\n\n\n"))
if err != nil {
    panic(err)
}

err = vm.Run(context.Background(), os.Stdin, os.Stdout)
if err != nil {
    panic(err)
}
```

`wspace.VM`では、コードの読み込み`vm.Load()`と実行`vm.Run()`が分かれています。
Whitespaceの文法上、ラベルの定義より前にそのラベルへのジャンプ命令が出現しうるため、
実行する前にコード全体を読み込んでおかないと適切にジャンプできません。

また、`vm.Load()`を複数回実行することで、VM内部の命令列（`vm.Program`）にプログラムを追記できるようにしました。
これにより、Jupyter上で最初のコードセルにサブルーチンを記述し、それを呼び出すコードを次のセルに分けて書くような使い方ができます[^19]。

[^19]: セルごとに実行されてしまうので、サブルーチンを記述するセルの先頭に終了命令を置くなど工夫が必要です

▼リスト18 `VM.Load()`メソッド
```go
// Load loads code segment to VM
// return: segment number, read size, error
func (*wspace.VM) Load(code []byte) (int, int, error)
```

コードの実行は`vm.Run()`で、入出力に`io.Reader`と`io.Writer`を渡します。
標準入出力以外を渡したいときも、これらのインターフェイスを実装することで対応できる、Go言語ではよくある形です。

▼リスト19 `VM.Run()`メソッド
```go
// Run the program.
func (*wspace.VM) Run(ctx context.Context, in io.Reader, out io.Writer) error
```

## カーネルへの組み込み

Jupyterからのコード実行リクエストは`"execute_request"`としてShellソケットに届きます。
`{content}`はリスト20のようなJSONで、`"code"`に実行すべきコードが入っています。

▼リスト20 execute_requestのcontent
```json
{
  "silent": false,
  "store_history": true,
  "user_expressions": {},
  "allow_stdin": true,
  "stop_on_error": true,
  "code": "   \t    \t\n\t\n  !"
}
```

カーネルにVMを組み込んでコードを実行するには、起動時にVMを初期化しておき、
この`"execute_request"`ごとに`vm.Load()`と`vm.Run()`を実行することになります。
これを組み込んだShellハンドラはリスト21のようになります。

▼リスト21 execute_requestを処理するShellハンドラ
```go
func (s *Sockets) shellHandler(vm *wspace.VM) {
    execCount := 0
    for {
        ... (略)

        // メッセージ種別による分岐
        switch hdr["msg_type"] {

        case "kernel_info_request":
            ... (略)

        case "execute_request":
            // "busy"状態に変更（処理を終えたら"idle"に戻す）
            s.sendState(msg, stateBusy)

            execCount++

            // 入力した場所から実行できるようにする
            vm.PC = len(vm.Program)
            vm.Terminated = false

            // コードの読み込み
            var content map[string]any
            _ = json.Unmarshal(msg.Content, &content)
            code := []byte(content["code"].(string))
            _, pos, err := vm.Load(code)
            if err != nil {
                s.sendStderr(msg, fmt.Sprintf("%v: %v", lineNum(code, pos), err.Error()))
                s.sendExecuteErrorReply(s.shell, msg, execCount, "LoadingError", err.Error())
                s.sendState(msg, stateIdle)
                continue
            }

            // 実行
            out := new(bytes.Buffer)
            in := &stdinReader{socks: s, parent: msg, stdout: out}
            err = vm.Run(context.Background(), in, out)
            if len(out.Bytes()) > 0 {
                s.sendStdout(msg, string(out.Bytes()))
            }
            if err != nil {
                op := vm.CurrentOpCode()
                s.sendStderr(msg,
                    fmt.Sprintf("%v: %v: %v", lineNum(code, op.Pos), op.Cmd, err.Error()))
                s.sendExecuteErrorReply(s.shell, msg, execCount, "RuntimeError", err.Error())
                s.sendState(msg, stateIdle)
                continue
            }

            s.sendExecuteOKReply(s.shell, msg, execCount)
            s.sendState(msg, stateIdle)
        }
    }
}
```

`"execute_request"`に限らず、Shellに届いたリクエストを処理するときは最初に状態を`"busy"`にし、処理を終えたら`"idle"`に戻します。
これを忘れるとリプライが正しく反映されないことがあります[^20]。

[^20]: ZeroMQのメッセージ送信は非同期で行われるため、Shellへのreply送信とIOPubへのbusy/idle通知の順序が入れ替わることがありえます。その際の挙動は未定義とされていて、ちょっと危ういシステムです。

### コードの読み込み

`wspace.VM`は読み込んだコードを命令列`vm.Program`とともに、
その実行位置を指し示すプログラムカウンタ`mv.PC`を持っています。
また、プログラム終了命令を実行したりエラーになって停止したことを示す`vm.Terminated`フラグもあります。

直前の実行で停止した場合、`vm.PC`は最後に実行した命令を指したままですし、
`vm.Terminated`が`true`になっていると続けて実行できません。
ここでは新たに読み込んだ場所から実行してほしいので、`vm.PC`を読み込み済みの`vm.Program`の末尾を指すようにし、
`vm.Terminated`も`false`にしておきます。

その後、送られてきたリクエストの`"code"`をそのまま`vm.Load()`で読み込みます。
読み込みエラー時は`stderr`にメッセージを表示してから`"execute_reply"`をエラーとして返すのですが、この詳細は後述します。

### 出力

`VM`からの出力は標準ライブラリの`bytes.Buffer`で受け取るようにしました。
実行中の出力をバッファリングしておき、終了後にまとめてJupyterの標準出力に送信します。

送信に使うメソッドはリスト22の`sendStdout()`です。
IOPubソケットに、メッセージタイプを`"stream"`、`{content}`に出力内容を入れて送信します。

▼リスト22 標準出力の送信メソッド
```go
func (s *Sockets) sendStdout(parent *Message, output string) {
    content, _ := json.Marshal(map[string]string{
        "name": "stdout",
        "text": output,
    })
    s.send(s.iopub, parent, "stream", content)
}
```

標準エラー出力にしたいときは、`{content}`の`"name"`を`"stderr"`にします。
これも`sendStderr()`として定義しました。

### 入力

Stdinソケットの使い方はShellソケットとは逆で、カーネルからJupyterに対してリクエストを投げます。
プログラムの実行中に標準入力を受け取る必要ができた時にリクエストを投げ、
それを受取ったJupyterは画面上に入力ボックスを表示します。
そしてユーザの入力をリプライとして返してくるので、カーネルはそれを受け取りプログラムに伝えます。

![input](/images/2024-06-04/input.png)
▲図2 入力ボックス

`VM`への入力は`io.Reader`、つまり`Read()`メソッドをもつインターフェイスです。
VMが入力を要求する命令を処理する時、この`Read()`メソッドを呼び出します[^21]。
したがって、`Read()`の中でStdinソケットにリクエスト投げてリプライを受け取り、それを返すような型を実装することになります。

そのような型として、`stdinReader`を実装しました（リスト23）。

[^21]: 実際の実装では効率化のため、`ReadByte()`も実装しています。

▼リスト23 stdinReader
```go
type stdinReader struct {
    socks  *Sockets
    parent *Message
    stdout *bytes.Buffer
    buf    []byte
}

func (i *stdinReader) Read(p []byte) (int, error) {
    // stdoutのフラッシュ 
    if out := i.stdout.Bytes(); len(out) > 0 {
        i.socks.sendStdout(i.parent, string(out))
        i.stdout.Reset()
    }

    buf := i.buf
    if len(buf) == 0 {
        // stdinをJupyterに要求し受け取る
        b, err := i.socks.getStdin(i.parent)
        if err != nil {
            return 0, err
        }
        buf = b
    }
    n := copy(p, buf)
    i.buf = buf[n:]
    return n, nil
}
```

`Read()`メソッドで最初に行っているのは、出力のフラッシュ処理です。
入力を求めるプログラムでは大抵、何を入力するのか示す文字列を出力してから入力を受け付けます。
たとえばWhitespaceのサンプルのCalculator[^22]では、次のように表示しています。
このような表示を先に出力するために、バッファリングされている出力をフラッシュするようにしました。

```
$ wspace calc.ws
Enter some numbers, then -1 to finish
Number:
```

[^22]: [https://web.archive.org/web/20150717115008/http://compsoc.dur.ac.uk/whitespace/calc.ws](https://web.archive.org/web/20150717115008/http://compsoc.dur.ac.uk/whitespace/calc.ws)

入力の要求と取得をしているのは、ちょうど中央あたりの`getStdin()`メソッドです。
この中でStdinソケットと通信しています。

Whitespaceで文字の入力を受け取るには、1文字ずつ読む命令を使います。
しかし、Jupyterでの入力テキストボックスは1行単位で入力するようになっているので、
毎回入力を要求して1文字しか使わないのは直感に反しますし、非効率です。
なので、ここでは受取った入力をバッファリングし、
バッファに入力が残っているときはJupyterへの要求はせずにバッファの内容を切り出して返すようにしています。

一方、このバッファリングされた入力は、次の`"execute_request"`には引き継ぎません。
`"execute_request"`はノートブックのセル単位で行われ、
入力のテキストボックスもそのセルのすぐ下の入出力エリアに表示されます。
このため、前のセルの実行時の入力が混ざってしまうのは望ましくないと考え、
`stdinReader`は`"execute_request"`ごとに初期化するようにしました。

続いて、Stdinソケットで入力を要求し受け取る`getStdin()`をリスト24に示します。

▼リスト24 Stdinソケットで通信するメソッド
```go
func (s *Sockets) getStdin(parent *Message) ([]byte, error) {
    s.sendRouter(s.stdin, parent, "input_request", []byte(`{"prompt":"","password":false}`))
    msg, err := s.recvRouterMessage(s.stdin)
    if err != nil {
        return nil, err
    }
    var d map[string]string
    _ = json.Unmarshal(msg.Content, &d)
    return append([]byte(d["value"]), '\n'), nil
}
```

StdinソケットはROUTERなので、メッセージを書き込むにはZmqIDが必要です。
ここではShellソケットで受信した`"execute_request"`のZmqIDと同じものを設定すれば大丈夫です。
というのも、Jupyter側でStdinにはShellと同じZmqIDを設定しているためです。

リクエストメッセージの`msg_type`は`"input_request"`で、`{content}`は`"prompt"`文字列と`"password"`フラグを指定します。
このメッセージを、Shellと同じように`sendRouterMessage()`で送信します。
するとJupyter上で入力のテキストボックスが表示されます。

テキストボックスに入力してエンターキーを押すと、Stdinソケットに`"input_reply"`メッセージが届きます。
`{content}`はリスト25のようになっています。

▼リスト25 `"input_reply"`の`{content}`
```json
{
  "status": "ok",
  "value": "hello"
}
```

入力値の`"value"`には末尾に改行は付いていません。
Whitespaceでは、数値の入力では末尾に改行（またはEOF）を要求します。
また、一般的な標準入力では、大抵のターミナルで行単位で末尾の改行を含めて入力されます。
この挙動に合わせたほうが都合がよいので、改行文字`'\n'`を末尾に追加して入力値としました。

### `"execute_reply"`

コードの実行が終わったら`"execute_reply"`を送信します。
`{content}`はリスト26のようなJSONです。
`"execution_count"`はJupyter上で実行したコードの左に表示される番号です。
`"execute_request"`を処理する毎に`execCount`をインクリメントしてこの値としています。

▼リスト26 execute_replyのcontent
```json
{
    "status": "ok",
    "execution_count": 1
}
```

エラー時は`"status"`を`"error"`にするほか、
エラーの名前と内容を示す`"ename"` `"evalue"`などのフィールドを加えますが、Jupyter上には表示されないようです。
ユーザーに見せるメッセージは`stderr`へ出力するようにしましょう。

▼リスト27 `"execute_reply"`を送信するメソッド
```go
func (s *Sockets) sendExecuteOKReply(sock *zmq4.Socket, parent *Message, count int) {
    content := fmt.Sprintf(`{"status":"ok","execution_count":%d}`, count)
    s.sendRouter(sock, parent, "execute_reply", []byte(content))
}

func (s *Sockets) sendExecuteErrorReply(
    sock *zmq4.Socket, parent *Message, count int, ename, evalue string) {

    content, _ := json.Marshal(map[string]any{
        "status":          "error",
        "execution_count": count,
        "ename":           ename,
        "evalue":          evalue,
        "traceback":       []any{},
    })
    s.sendRouter(sock, parent, "execute_reply", content)
}
```

これでWhitespaceをJupyter上で実行できるようになりました。
余談ですが、Jupyterは空文字列しかないセルは実行してくれません（`"execute_request"`を送信してくれません）。
Whitespaceのコードを実行するときは最低1文字は見える文字を混ぜておく必要があります。

## おわりに

この章では、Jupyterのカーネルの実装方法を、Whitespaceのカーネル「whitenote」のコードを使って解説しました。
細かいお約束が多いため長くなってしまいましたが、必要な実装はそれほど多くなく、
シンプルな仕組みになっていることが分っていただけたと思います。

ぜひ皆さんも、お気に入りの言語のJupyterカーネルを自作してみてください。

---

### コラム: タブ文字を入力するには
JupyterのコードセルでWhitespaceのコードを入力しようとすると、タブキーを押してもタブ文字が入力されないことに気づくと思います。
これは、タブキーがコード補完に割り当てられているためです。

Jupyterがコードを補完するとき、カーネルには`"complete_request"`が送られます。
ここで補完候補を複数返すとJupyter上で選択するUIが表示されますが、候補が1つしかないときは直接それが入力されます。

つまり、`"complete_request"`に対してタブ文字だけを補完候補として返すことで、タブ文字を入力できるようになります。
実装の詳細はwhitenoteのリポジトリをご覧ください。

ただし、行頭から空白文字しかない場合は補完ではなく、自動インデントになってしまいます。（しかもタブ文字ではなくスペースで！）
この挙動はJavascriptのCodeMirror[^23]によるもので、カーネルからは挙動を変えられそうにはありません。

Whitespaceを記述するときは行頭になにか見える文字を入力しておくと快適に入力できます。

---

[^23]: [https://codemirror.net/](https://codemirror.net/)
