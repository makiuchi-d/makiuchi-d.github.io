---
layout: post
title: "オンライン対戦を支える独自シリアライズフォーマット (KLabTechBook Vol.9)"
---

この記事は2022年1月22日から開催された[技術書典12](https://techbookfest.org/event/tbf12)にて頒布した「KLabTechBook Vol.9」に掲載したものです。

現在開催中の[技術書典16](https://techbookfest.org/event/tbf16)オンラインマーケットにて新刊「[KLabTechBook Vol.13](https://techbookfest.org/product/3CTYX4wj9wwBr13qJRYwA5)」を頒布（電子版無料、紙+電子 500円）しています。
また、既刊も在庫があるものは物理本を[オンラインマーケット](https://techbookfest.org/organization/5654456649646080)で頒布しているほか、
[KLabのブログ](https://www.klab.com/jp/blog/tech/2024/tbf16.html)からもすべての既刊のPDFを無料DLできます。
合わせてごらんください。

[<img src="/images/2024-05-29/ktbv13.jpg" width="40%" alt="KLabTechBook Vol.13" />](https://techbookfest.org/product/3CTYX4wj9wwBr13qJRYwA5)

--------

<p style="background-color:lightcyan;border-left:0.3em solid cyan;padding:0.5em">
<strong>ℹ️</strong>
この記事で言及している同期通信基盤は、その後「<a href="https://github.com/KLab/wsnet2">WSNet2</a>」というOSSとしてGitHub上にて公開しています。
</p>

## はじめに

近年のモバイルオンラインゲームでは、対戦や協力プレイといった同期通信が当たり前になっています。
KLabでももちろんそのようなゲームをリリースしており、Photon[^1]のようなサードパーティのサービスを使うこともありますが、
いくつかのタイトルでは独自の同期通信の仕組みを使っています。
筆者はこの数年、この同期通信基盤の開発と運用に携わってきました。

KLabの多くのタイトルはUnityで制作していますが、この同期通信基盤では部屋管理とデータ中継のサーバーをGo言語で実装しており、
各クライアントからHTTPとWebSocketでこれらのサーバーに接続する構成を取っています。
また、さまざまなプロジェクトで同じサーバーをそのまま使えるような汎用的な作りにしています。

この章では、KLabの同期通信基盤のために開発した独自のシリアライズフォーマットについて、
その特徴や工夫した点を紹介したいと思います。

[^1]: https://www.photonengine.com/

## なぜ独自フォーマットが必要だったのか

ネットワークを介してデータを送信するには、何らかの方法でビット列に変換する必要があります。
そして受信したビット列は、元のデータに復元しなければプログラムからは利用できません。
クライアントはC#なので、値だけでなく型も送受信の前後で同じにならないと困ってしまいます。

C#同士だけであれば、C#の標準ライブラリの`System.Runtime.Serialization`を使うこともできるかもしれません。
しかし今回作っているものは、部屋を管理するためにGo製のサーバーでもデータを読み取る必要があるため、Goでも読み取りやすい形式が必要でした。

世の中にはC#でもGoでも、あるいは他の言語でも使えるような汎用フォーマットもあります。
しかし、たとえばJSONやMessagePack[^2]ではC#よりも型が少ないため送信元の型を完全に復元することができませんし、
C#のときの型がGoからは分らなくなってしまいます。
あるいはProtocolBuffers[^3]のように共通の定義から事前にコード生成するものもありますが、
利用するデータ型を追加するためにはクライアントだけでなくサーバーも合わせて更新する必要があります。
これでは多くのプロジェクトで使える共通のサーバーを作るには不向きです。
できるならクライアントだけで独自のデータ型を追加できるのが理想です。

[^2]: https://msgpack.org/
[^3]: https://developers.google.com/protocol-buffers

このようなニッチな要求を満たすものはまず存在しないので作ることにしました。
ここで紹介するシリアライザはGitHubにて公開しています[^4]。
あわせてご覧ください[^5]。

[^4]: https://github.com/KLab/wsnet2-serializer
[^5]: 紙面に掲載したコード片は一部簡略化などの変更をしています

## 独自フォーマットの特徴

C#のプリミティブ型に加え、独自定義型も特定インターフェイスを実装することでシリアライズできます。
加えて、シリアライズ可能な型を要素にもつリストや配列、文字列キーの辞書型もサポートし、ネストもできます。

この辞書型は部屋のプロパティとしても利用しており、Goでも辞書（`map`）として扱うためにキーの型を固定する必要がありました。
Photonでも部屋のプロパティ（`RoomInfo.CustomProperties`）は文字列キーの辞書を採用していますし、扱いやすさを優先して文字列キーとしました。

またGoでリストや辞書をデシリアライズするとき、各要素をバイト列のスライス（`[]byte`）のまま保持し、
必要になるまでデシリアライズしない遅延デシリアライズを実現したほか、
同じ型同士の単純な大小比較であればバイト列のまま比較できるようにしました。
このメリットは後ほど紹介したいと思います。

クライアント側C#の実装も、パフォーマンス対策としてboxingの回避やオブジェクトの再利用ができるよう実装しています。
その詳細はリポジトリの`SerialReader`、`SerialWriter`クラスをご覧いただくとして、
ここではフォーマットの概要を説明します。

## フォーマットの概要

基本的には、1byteの型情報とそれに続く型ごとのデータのバイト列で構成されます。
扱える型は先述のとおり、C#のほとんどのプリミティブ型と、独自定義型、シリアライズ可能な型のリストや辞書です。

![基本的な形](/images/2024-06-02/format.png)
<br />▲図1 基本的な形

▼表1 型情報と対応するC#の型一覧

0: Null|11: ULong (`ulong`)|22: Bytes (`byte[]`)
1: False (`bool`)|12: Float (`float`)|23: Chars (`char[]`)
2: True (`bool`)|13: Double (`double`)|24: Shorts (`short[]`)
3: SByte (`sbyte`)|14: Decimal (`decimal`)[^6]|25: UShorts (`ushort[]`)
4: Byte (`byte`)|15: Str8 (`string`)|26: Ints (`int[]`)
5: Char (`char`)|16: Str16 (`string`)|27: UInts (`uint[]`)
6: Short (`short`)|17: Obj (独自定義クラス)|28: Longs (`long[]`)
7: UShort (`ushort`)|18: List (`List<object>`)|29: ULongs (`ulong[]`)|
8: Int (`int`)|19: Dict (`Dictionary<string, object>`)|30: Floats (`float[]`)
9: UInt (`uint`)|20: Bools (`bool[]`)|31: Doubles (`double[]`)
10: Long (`long`)|21: SBytes (`sbyte[]`)|32: Decimals (`decimal[]`)[^6]

[^6]: `decimal`型は定義していますが未実装です

ここからはそれぞれの型について、その型ごとのシリアライズ方法を解説していきます。

### Null値とbool型

さきほど、フォーマットの基本は1byteの型とそれに続くデータと説明しましたが、いきなり例外的なものたちです。
`bool`型は`true`または`false`ですが、それを型情報に加えて1byteのデータで表すのはもったいないので、
型情報をTrueとFalseの2種類に分け、データを持たない形としました。
また、Null値は型をもたない`null`として、これも1byteの型情報のみで表現します。
このようなやり方はMessagePackを参考にしました。

リスト1にbool型のシリアライズとデシリアライズのC#実装を掲載します。
boxingを避けるために、書き込み（`Write`メソッド）は引数の型でメソッドオーバーロードし、
読み出しは型ごとのメソッド（`Read+型名`）を定義しています。

▼リスト1 bool型のシリアライズ・デシリアライズ
```csharp
public class SerialWriter
{
    int    pos; // 書き込み位置
    byte[] buf; // 書き込みバッファ
    (略)
    /// <summary>Bool値を書き込む</summary>
    public void Write(bool v)
    {
        expand(1);                                     // バッファが足りなければ1byte拡張
        buf[pos] = (byte)(v ? Type.True : Type.False); // 型情報としてTrueかFalseを書き込む
        pos++;
    }
    (略)
}

public class SerialReader
{
    (略)
    /// <summary>Bool値として読み出す</summary>
    public bool ReadBool()
    {
        var t = checkType(Type.True, Type.False);
        return t == Type.True;
    }
    (略)
    /// <summary>先頭1byteを読み、引数のTypeだったらそれを返し、それ以外のときは例外送出</summary>
    Type checkType(Type want1, Type want2)
    {
        checkLength(1);               // 1byte以上あるか確認
        var t = (Type)buf[pos];
        if (t != want1 && t != want2)
        {
            throw new SerializationException("invalid type");
        }
        pos++;
        return t;
    }
}
```

### 整数型、浮動小数点数型

整数型は1byteの型情報に続けて、数値をBigEndianで書き込みます。
MessagePackのように節約したフォーマットではなく、64bitの`long`型はそのまま8byteで記録する単純な形です。
このとき、符号なし整数はそのままですが、符号付き整数は下駄履き表現、つまり`short`の場合`128`を加えて、
`-128`を`127`を`255`となるようにして書き込みます。
こうすることで、バイト列を先頭から単純に比較していくだけで、元の値の大小関係が分かるようになります。

▼リスト2 符号付きshort型のシリアライズ・デシリアライズ
```csharp
public class SerialWriter
{
    (略)
    /// <summary>Short値を書き込む</summary>
    public void Write(short v)
    {
        expand(3);
        buf[pos] = (byte)Type.Short;
        pos++;
        var n = (int)v - (int)short.MinValue; // 下駄履き表現に変換
        Put16(n);
    }
    (略)
    /// <summary>16bit値をBigEndianで書き込む</summary>
    public void Put16(int v)
    {
        buf[pos] = (byte)((v & 0xff00) >> 8);
        buf[pos+1] = (byte)(v & 0xff);
        pos += 2;
    }
    (略)
}

public class SerialReader
{
    (略)
    /// <summary>Short値として読み出す</summary>
    public short ReadShort()
    {
        checkType(Type.Short);
        return (short)(Get16() + (int)short.MinValue); // 下駄履き表現から戻す
    }
    (略)
    /// <summary>16bit値を読み出す</summary>
    public int Get16()
    {
        checkLength(2);
        var n = (int)buf[pos] << 8;
        n += (int)buf[pos+1];
        pos += 2;
        return n;
    }
    (略)
}
```

浮動小数点数でもIEEE 754の表現からビット操作して、整数型と同じようにバイト列のまま大小比較できるようにしました。
詳しくは筆者のblog記事[^7]をご覧ください。

[^7]: http://makiuchi-d.github.io/2020/12/09/float-comparable.ja.html

### 文字列型

文字列型は可変長なので、1byteの型情報に続けてデータ長を書いておきます。
ゲームで通信しあう文字列は短いものが多いので、データ長は1byteで表現したいところですが、
チャットのような機能を作る場合は255文字では足りないかもしれません。
そこで型情報をStr8とStr16の2つに分け、255byte以下は前者で文字列長を1byte、それ以上長いものは後者で文字列長を2byteとしました。

データのエンコーディングはUTF-8とします。
これはGoの文字列の内部エンコーディングがUTF-8なので、バイト列からそのまま文字列にキャストできるようにするためです。

▼リスト2 文字列型のシリアライズ・デシリアライズ
```csharp
public class SerialWriter
{
    (略)
    /// <summary>文字列を書き込む</summary>
    public void Write(string v)
    {
        if (v == null)
        {
            Write(); // Type.Null書き込み
            return;
        }

        var len = utf8.GetByteCount(v); // UTF-8でのデータ長
        if (len <= byte.MaxValue)
        {
            expand(len+2);
            buf[pos] = (byte)Type.Str8;
            pos++;
            Put8(len); // 1byteでデータ長を記録
        }
        else if (len <= ushort.MaxValue)
        {
            expand(len+3);
            buf[pos] = (byte)Type.Str16;
            pos++;
            Put16(len); // 2byteでデータ長を記録
        }
        else
        {
            throw new SerializationException("too long");
        }

        utf8.GetBytes(v, 0, v.Length, buf, pos); // UTF-8として書き込み
        pos += len;
    }
    (略)
}

public class SerialReader
{
    (略)
    /// <summary>文字列として読み出す</summary>
    public string ReadString()
    {
        var t = checkType(Type.Str8, Type.Str16, Type.Null);
        if (t == Type.Null)
        {
            return null;
        }
        // データ長はStr8なら1byte, Str16なら2byte
        var len = (t == Type.Str8) ? Get8() : Get16();
        var str = utf8.GetString(buf, pos, len);
        pos += len;
        return str;
    }
    (略)
}
```

### 独自定義クラス

独自定義クラスをシリアライズできるようにするには、`IWSNet2Serializable`インターフェイスを実装し、
`WSNet2Serializer.Register`メソッドでClassIDを事前に登録する必要があります。
このClassIDとクラスの対応関係は通信するすべてのクライアントで一致している必要があります。
クライアントは基本的に同じソースからビルドするはずなので、一致させるのは容易でしょう。

▼リスト3 IWSNet2SerializableインターフェイスとRegisterメソッド
```csharp
public interface IWSNet2Serializable
{
    void Serialize(SerialWriter writer);
    void Deserialize(SerialReader reader, int size);
}

public class WSNet2Serializer
{
    public delegate object ReadFunc(SerialReader reader, object recycle);

    static Hashtable registeredTypes = new Hashtable(); // 型->ClassIDのマッピング
    static ReadFunc[] readFuncs = new ReadFunc[256];
    (略)
    /// <summary>独自定義クラスを登録</summary>
    public static void Register<T>(byte classID) where T : class, IWSNet2Serializable, new()
    {
        var t = typeof(T);
        registeredTypes[t] = classID;

        // SerialReader.ReadObject<T>() は型Tがわからないと呼べない
        // ClassIDだけから呼び出せるように無名関数を保持しておく
        readFuncs[classID] = (reader, obj) => reader.ReadObject<T>(obj as T);
    }
    (略)
}
```

シリアライズ後のデータは図2のような形になります。
ClassIDが1byteなため登録できるクラスは256種類に限られますが、普通のゲームであれば十分な数です。
また、ClassIDの後にデータサイズがあることで、中身をデシリアライズすることなくデータを切り出すことができます。
これにより、データ部分をバイト列として切り出しておき、必要になってからデシリアライズする遅延デシリアライズができます。

![独自定義クラスのシリアライズイメージ](/images/2024-06-02/serialobj.png)
▲図2 独自定義クラスのシリアライズイメージ

ここでリスト4に独自定義クラスの例として、チェスの駒を表すクラスを定義してみます。

▼リスト4 独自定義クラスの例
```csharp
public class ChessPiece
{
    public PieceType Type;
    public int PositionX;
    public int PositionY;

    public void Serialize(SerialWriter writer)
    {
        writer.Write((byte)Type); // PieceTypeは1byteで
        // 盤面は8x8なので座標も1byteにまとめて
        writer.Write((byte)(PositionX * 8 + PositionY));
    }

    public void Deserialize(SerialReader reader, int size)
    {
        Type = (PieceType)reader.ReadByte();
        var pos = writer.ReadByte();
        PositionX = pos / 8;
        PositionY = pos % 8;
    }
}
```

`Serialize`メソッドでは`SerialWriter`経由でデータを書き込んでいくため、
書き込み毎に型情報が付加される形でシリアライズされます。
若干冗長な気もしますが、このおかげでGoでも独自定義クラスの中にどのような型の値が含まれているか読み取ることができます。

またチェスの盤面は8×8なので、XとYの座標を1byteにまとめることで通信量を減らしています。
ゲームで使うオブジェクトでは、このようなゲーム仕様に基づく最適化ができたり、マスタデータのIDなど一部のメンバだけ送れば済むようなケースがよくあります。
このため、リフレクションを使った自動的なシリアライズなどは行わず、若干面倒かもしれませんが自分で書く形としました。
`Serialize`と`Deserialize`で対応がとれていないと正しく動かなくなってしまいますが、ユニットテストで担保するとよいでしょう。

▼リスト5 独自定義クラスのシリアライズ・デシリアライズ
```csharp
public class SerialWriter
{
    (略)
    /// <summary>独自定義クラスのオブジェクトを書き込む</summary>
    public void Write<T>(T v) where T : class, IWSNet2Serializable
    {
        if (v == null)
        {
            Write(); // nullのときは型なしNullを書き込むだけ
            return;
        }

        var t = v.GetType();
        var id = types[t];

        expand(4);
        buf[pos] = (byte)Type.Obj;
        buf[pos+1] = (byte)id;     // ClassID 書き込み
        pos += 4;                  // サイズを書き込む領域分進める
        var start = pos;

        v.Serialize(this); // 独自定義クラスのSerialize()呼び出し

        // Serializeで書き込んだサイズを埋める
        var size = pos - start;
        buf[start-2] = (byte)((size & 0xff00) >> 8);
        buf[start-1] = (byte)(size & 0xff);
    }
    (略)
}

public class SerialReader
{
    (略)
    /// <summary>独自定義クラスとして読み出す</summary>
    public T ReadObject<T>(T recycle = default) where T : class, IWSNet2Serializable, new()
    {
        if (checkType(Type.Obj, Type.Null) == Type.Null)
        {
            return null;
        }

        var cid = classIDs[typeof(T)];
        var id = (byte)Get8();
        if (id != (byte)cid)
        {
            throw new SerializationException("class id mismatch");
        }

        var size = Get16();
        checkLength(size);

        var obj = recycle;
        if (obj == null) {
            obj = new T();
        }

        var start = pos;
        obj.Deserialize(this, size);
        pos = start + size;

        return obj;
    }
    (略)
}
```

デシリアライズする`ReadObject<T>`メソッドでは、`recycle`というオブジェクトを引数として受け取ります。
データ受信時にオブジェクトを新たに作るのではなく再利用することで、メモリアロケーションを減らすことができます。

### リストと辞書

リスト型は型情報に続いて1byteの要素数、その後にシリアライズした要素のデータ長とデータがが繰り返し配置される形でシリアライズされます。
それぞれの要素データは、型情報とその型ごとのデータのバイト列からなる、シリアライズされたデータです。
このような構造のため、何重にもネストすることができます。

![リスト型のシリアライズイメージ](/images/2024-06-02/seriallist.png)
▲図3 リスト型のシリアライズイメージ

辞書型もリスト型と同じように、1byteの要素数と要素の繰り返しからなる形です。
各要素は1byteのキー長、キー文字列データ、シリアライズした要素のデータ長とデータが並びます。

![辞書型のシリアライズイメージ](/images/2024-06-02/serialdict.png)
▲図4 辞書型のシリアライズイメージ

リストも辞書も、各要素データの長さがデータの前にあることで、要素の中身をデシリアライズすることなくバイト列として切り出すことができます。
特に辞書型は部屋のプロパティとしても使われていて、データを切り出せることがGoでの扱いやすさに繋がっています。
これについては後で解説します。

### プリミティブ型の配列

`int[]`のようなプリミティブ型の配列は、`int`がシリアライズ可能なのでリスト型としてもシリアライズできます。
しかし、リスト型では要素ごとにサイズや型情報が入り効率がよくありません。
なので、数値型やbool型の配列は専用の型としてシリアライズできるようにしました。

型によって要素データのサイズは固定なので、リストのようにデータサイズを書き込まず、
単純に値だけをシリアライズしたデータを並べます。
さらにbool型の配列は1ビット単位で効率的に格納します。

![int型配列のシリアライズイメージ](/images/2024-06-02/serialints.png)
▲図5 辞書型のシリアライズイメージ

## サーバーでの部屋のプロパティ

各部屋には、クライアントが自由に設定できるプロパティとして、文字列キーの辞書を用意しています。
このプロパティは部屋にいる全クライアントに共有される他、部屋の検索やランダム入室の際のフィルタリングにも利用します。

この辞書は、Goのサーバーでは`map[string][]byte`型になっていて、
辞書の各要素の値はバイト列（`[]byte`）のままデシリアライズせずに保持しています。

### プロパティの値の変更

プロパティの値を変更するときは、リスト6のように変更するキーと値だけの辞書をクライアントから送ります。

▼リスト6 クライアントから送る辞書型データ
```csharp
var dict = new Dictionary<string, object>()
{
    {"Turn", 1},
    {"WhitePawn4", new ChessPiece(){ Type=PieceType.Porn, PositionX=3, PositionY=4 }},
};

room.ChangeRoomProperty(publicProps=dict);
```

Goの中継サーバーはこの辞書を@<list>{readdic}のようにデシリアライズし、文字列キーと値データのバイト列を取り出します。

▼リスト7 Goでの辞書のデシリアライズ
```csharp
type Dict map[string][]byte

func unmarshalDict(src []byte) (Dict, int, error) {
    count := get8(src[1:]) // 要素数
    l := 2
    dict := make(Dict)
    for i := 0; i < count; i++ {
        lk := get8(src[l:])     // キー長
        l += 1
        key := src[l : l+lk]    // キーデータ
        l += lk
        lv := get16(src[l:])    // データ長
        l += 2
        dict[string(key)] = src[l : l+lv] // データのバイト列
        l += lv
    }
    return dict, l, nil
}
```

このようにサーバー側での辞書のデシリアライズでは、各要素の値のデータをバイト列のスライスとして切り出しています。
Goのスライスは元の配列の参照になっているため、メモリのコピーが発生せず高速です。
そしてこのスライスをそのまま部屋のプロパティとして保持します。

## 部屋のフィルタリング

部屋検索では部屋のプロパティを参照する柔軟なフィルタリングができるようにしました。
フィルタリングの条件は、たとえば「レベル10~15の範囲かつ、赤チームまたは黄色チーム」はリスト8のような形[^8]で指定します。

[^8]: 実際には、HTTPのBodyにMessagePack形式で他のパラメータとともにこのようなフィルタ条件を入れて送っています

▼リスト8 フィルタリング条件のイメージ
```json
[
    [
        {"Team", Equal, (byte)Team.Red},
        {"Level", GreaterOrEqual, 10},
        {"Level", LessOrEqual, 15}
    ],
    [
        {"Team", Equal, (byte)Team.Yellow},
        {"Level", GreaterOrEqual, 10},
        {"Level", LessOrEqual, 15}
    ]
]
```

このように条件を`{キー, 演算子, 値}`の二重配列として表し、内側の配列はAND結合、外側はOR結合にしています。
どんなに複雑な条件指定も、分配法則やド・モルガンの法則で変換すれば必ずこの形に変形できます。

この形にしておくと、サーバー側はリスト9のようにシンプルなループでフィルタリングできます。

▼リスト9 フィルター
```csharp
type PropQuery struct {
     Key string
     Op  OpType // operation type (==, !=, <, <=, >, >=)
     Val []byte // value
}

func filter(rooms []*Room, queries [][]PropQuery) []*Room {
    filtered := make([]*Room, 0)

    for _, room := rooms {

        // OR結合：一つでもマッチしている条件群があればRoomを追加
        for _, qs := queries {

            // AND結合：全てマッチしていたらこの条件群はマッチ
            match := true
            for j := range queries[i] {
                if !queries[i][j].match(room.Property[queries[i][j].Key]) {
                    match = false
                    break
                }
            }

            // マッチしていたので結果に追加
            if match {
                filtered = append(filtered, room)
                break
            }
        }
    }
    return filtered
}
```

値の比較はこれまで説明してきたとおり、バイト列をそのままバイト単位で比較します。
数値型の場合、型が一致していれば大小関係もバイト列のまま比較できます。
このようなサーバー側の実装だけでは、数値以外でも大小関係の比較を指定できてしまう形式なのですが、
そこはクライアント側のフィルタ条件生成クラスで大小比較は数値型だけになるように担保しています。

▼リスト10 マッチするか判定
```csharp
func (q *PropQuery) match(val []byte) bool {
    ret := bytes.Compare(val, q.Val) // バイト列のまま比較
    switch q.Op {
    case OpEqual:
        return ret == 0
    case OpNot:
        return ret != 0
    case OpLessThan:
        return ret < 0
    case OpLessOrEqual:
        return ret <= 0
    case OpGreaterThan:
        return ret > 0
    case OpGreaterOrEqual:
        return ret >= 0
}
```

## さいごに

この章では、KLabの同期通信基盤の独自のシリアライズフォーマットを紹介しました。
汎用性を犠牲にして自分たちの用途に合わせているため、そのまま使える場面は少ないと思いますが、
細かい工夫点やテクニックが何かの参考になれば幸いです。

また、シリアライザだけでなくこの同期通信基盤そのものについても、
今後何らかの発表をしていきたいと思っておりますのでご期待下さい。
