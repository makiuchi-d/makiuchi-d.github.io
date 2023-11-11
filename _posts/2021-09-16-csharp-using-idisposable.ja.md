---
layout: post
title: C#でIDisposableをusingしたのにDisposeしてくれない件
---

C#でdotnetコンソールプログラムを開発中、例外発生時にログファイルが欠損する問題に直面しました。
ロガーは`IDisposable`を実装し`Dispose()`でログをFlushするするようにしてあり、using構文（[using宣言](https://docs.microsoft.com/ja-jp/dotnet/csharp/whats-new/csharp-8#using-declarations)または[usingステートメント](https://docs.microsoft.com/ja-jp/dotnet/standard/garbage-collection/using-objects#the-using-statement)）でDisposeするようにしていました。
このため、どんなときでも確実にログはFlushされると期待していました。

しかし、実際には例外発生時にログはFlushされることなく欠損してしまいました。
なぜそうなったのか、どうすれば正しく動くのか書き残します。

## 検証用プログラム

**Program.cs**
```csharp
using System;

public class C : IDisposable
{
    public void Dispose()
    {
        Console.WriteLine("dispose");
        Console.Out.Flush();
    }
}

class Program
{
    public static void Main(string[] args)
    {
        using var c = new C();
        throw new Exception();
    }
}
```

**testapp.csproj**
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net5.0</TargetFramework>
  </PropertyGroup>
</Project>
```

クラス`C`は`IDisposable`を実装し、`Disposse()`でConsoleに文字列を出力・flushしています。
`Main()`ではこのクラス`C`のオブジェクトをusing宣言で変数に格納し、直後に例外を投げています。

**実行結果（Ubuntu 20.04.3 LTS; dotnet 5.0.400）**
```console
$ dotnet run
Unhandled exception. System.Exception: Exception of type 'System.Exception' was thrown.
   at Program.Main(String[] args) in /home/makki/Projects/testapp/Program.cs:line 18
```

この挙動は実は環境依存なのですが、僕の環境では`c.Dispose()`が処理されることなく例外でプログラムが終了してしまいました。
これではせっかくIDisposableを実装しても意味がありません。

## 実行されないfinally

ご存知の通り、using構文は次のtry-finally構文と等価です。
実際、usingから次のように書き換えても全く同じ挙動になります。

```csharp
    public static void Main(string[] args)
    {
        C c = null;
        try
        {
            c = new C();
            throw new Exception();
        }
        finally
        {
            c?.Dispose();
        }
    }
```

なぜfinallyの内容が実行されなかったのか、そのヒントは[try-finallyのドキュメント(Internet Archive)](https://web.archive.org/web/20220211193315/https://docs.microsoft.com/ja-jp/dotnet/csharp/language-reference/keywords/try-finally)にありました。

> ハンドルされている例外では、関連する finally ブロックの実行が保証されます。 ただし、例外がハンドルされていない場合、finally ブロックの実行は、例外のアンワインド操作のトリガー方法に依存します。 つまり、コンピューターの設定に依存するということでもあります。 finally 句が実行されないのは、プログラムが直ちに停止している場合のみです。 これの例は、IL ステートメントが壊れているために InvalidProgramException がスローされる場合です。 ほとんどのオペレーティング システムでは、プロセスの停止とアンロードの一環として、リソースの適切なクリーンアップが行われます。

<p style="background-color:bisque;border-left:0.3em solid orange;padding:0.5em">
<strong>⚠ .NETのドキュメントが更新されました</strong> (2023/11/11追記)<br>
ここで引用していたページが削除され、別ページにリダイレクトされるようになっていました。
確認できるよう、リンクをInternetArchiveのものに置き換えてあります。

なお、.NET 7.0においても、Linux版での動作はこの記事執筆時と変わっていません。
</p>

よく読むと「例外がハンドルされていない場合、環境によってはfinally句が実行されないことがある」と書かれているではありませんか。
例外を握りつぶしたりしないお行儀の良いプログラムを書いたことで、逆に期待通りに動いてくれない罠にはまっていたわけです。

## どうすればよいのか

using構文を使っても例外発生時にDisposeされなかったのは、等価なtry-finally構文においてfinally句が実行されていなかったからです。
finally句が実行されないのは例外がハンドルされていない場合であり、ハンドルされているならfinally句の実行は保証されます。

問題のコードを次のように書き換えてみましょう。

```csharp
    public static void Main(string[] args)
    {
        try
        {
            using var c = new C();
            throw new Exception();
        }
        catch
        {
            throw;
        }
    }
```

`Main()`の中の一番外側をtry-catchで囲み、例外をcatchしたらすぐthrowしているだけです。
このように例外を一旦catchすることでようやくfinally句の実行が保証され、usingしたIDisposableなオブジェクトも確実にDisposeされるようになります。

## まとめ

C#のusing構文はとてもわかりやすく便利ですが、ただusingするだけではDisposeしてくれない無意味な文になってしまう場合があります。
usingする外側では、例外のcatchを絶対に忘れないようにしましょう。
