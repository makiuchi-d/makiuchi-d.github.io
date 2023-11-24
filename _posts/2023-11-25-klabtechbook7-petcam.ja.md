---
layout: post
title: "Raspberry PiとGoogle Meetでお手軽ペットカメラ (KLabTechBook Vol.7)"
---

この記事は2020年12月26日から開催された[技術書典10](https://techbookfest.org/event/tbf10)にて頒布した「KLabTechBook Vol.7」に掲載したものです。

現在開催中の[技術書典15](https://techbookfest.org/event/tbf15)オンラインマーケットにて新刊「[KLabTechBook Vol.12](https://techbookfest.org/product/d20GG5Femwp1rTWSveSiHF)」を頒布（電子版無料、紙+電子 500円）しています。
また、既刊も在庫があるものは物理本を[オンラインマーケット](https://techbookfest.org/organization/5654456649646080)で頒布しているほか、
[KLabのブログ](https://www.klab.com/jp/blog/tech/2023/tbf15.html)からもすべての既刊のPDFを無料DLできます。
合わせてごらんください。

[<img src="/images/2023-11-11/ktbv12.jpg" width="40%" alt="KLabTechBook Vol.12" />](https://techbookfest.org/product/d20GG5Femwp1rTWSveSiHF)

--------

<p style="background-color:bisque;border-left:0.3em solid orange;padding:0.5em">
<strong>⚠ 古い情報です</strong><br>
KLabTechBook Vol.7掲載当時のままにしてあるため、
ハードウェアの情報も古くGoogleのサービスの挙動も変わっており、この記事のとおりには動作しません。
ご注意ください。
</p>

皆さんは犬派ですか？猫派ですか？

今年はCOVID-19の影響でリモートワークを採用する企業が増えました。
家にいる時間が長くなったことで、ペットを飼い始めた方も多いのではないのでしょうか。
KLabでもほとんどの社員がリモートワークとなったことで[^1]、ちょっとしたペットブームになっているようです。
筆者も保護猫兄弟を家族に迎えました。

リモートワークとはいえ、まったく外出しないわけにはいきません。
しかし、ペットだけの留守番は何かと不安です。
そんなとき、ペットカメラで出先からペットの様子を確認できたら安心ですね。

[^1]: [在宅勤務率は約99％ 新型コロナウイルス感染症対策のこれまでの取り組みについて](https://www.klab.com/jp/press/release/2020/0427/99.html)

## 市販のペットカメラについて

ペットカメラとここでは呼びますが、要するにネットワークカメラです。
ペット用はもちろんのこと介護や防犯目的のものも含め、多種多様な製品が販売されています。
これらの製品の多くはペットカメラ自体が動画配信サーバーとなり、
出先からはインターネットを介して直接そのサーバーに接続することで映像を見れるようになっています。

インターネットから直接アクセスするためにはグローバルIPアドレスが必要です。
しかし筆者の場合、建物全体がLANになっている集合住宅に住んでいるため、グローバルIPアドレスがありません。
そのため、ペットカメラがサーバーとなる製品はそもそも選択肢になりませんでした。

加えて、直接アクセスされる製品の場合、セキュリティに気を配らないとペットカメラの制御が奪われて映像を盗み見られたり、
そこを起点に自宅LAN内の他の機器へ侵入されたりする可能性もあります。

そんなわけで、筆者は家に転がっていたRaspberry Piをよりセキュアなペットカメラに仕立て上げることにしました。


## ハードウェア構成

<img src="/images/2023-11-25/hardware.jpg" width="40%" alt="全体像"/>
<br />▲図1 全体像

### Raspberry Pi

たまたま家で余っていたRaspberry Pi 3Bを使いました。
3Bでもメモリ容量は足りているので、新しく購入するなら4Bの2GBモデル[^2]が良さそうです。

[^2]: [Raspberry Pi 4 Model B/2GB](https://amzn.to/36uK2Ye)

### カメラモジュール

魚眼レンズのものを選ぶと広い範囲を映せて便利です。
さらに夜間も映したい場合は、ナイトビジョン対応で赤外線LEDの付く製品[^3]がお勧めです。

そのような機能が不要であれば、Raspberry Pi専用ではない一般的なUSBウェブカメラでも十分です。

[^3]: たとえば [こんなカメラモジュール](https://amzn.to/3sG1xTs) と [赤外線LED](https://amzn.to/3sD0V0U)


### マイク

無くてもよいですが、シンプルなUSBマイク[^4]を付けると音声も聞き取れるようになります。

[^4]: たとえば [こんなUSBマイク](https://amzn.to/33AyEbu)

### その他

他にも[図1](#ハードウェア構成)に写っているとおり、スマートリモコンを実装した基板を搭載しています。
単純なペットカメラには不要ですが、これについては後述します。

## 映像配信方法

ペットカメラ自体を配信サーバーにするのではなく、外部のビデオ通話サービスを利用する形にしました。
そうすることで、グローバルIPアドレスが無くても出先から映像を見ることができますし、
直接自宅LAN内にアクセスさせなくて済むため、セキュリティ上の不安もありません。

ビデオ通話サービスはいくつもありますが、ここではGoogle Meet[^5]を利用します。
Google MeetはWebブラウザで完結するので、Puppeteer[^6]やSelenium[^7]による自動化が可能です。
また、無料版のGoogle Meetには通話あたりの時間制限[^8]はあるものの通話数は無制限のため、
新しい通話に切り替えていくことで[^9]実質24時間365日の稼働が可能となります[^10]。
さらに専用アカウントで運用すれば、万が一アカウントが奪取されても被害は最小限で済みます。

また、出先からアクセスするのも特別な設定は一切不要で、普通にGoogle Meetの通話に参加するだけなのでお手軽です。

[^5]: [Google Meet](https://meet.google.com/)
[^6]: [Puppeteer](https://pptr.dev/)
[^7]: [Selenium](https://www.selenium.dev/)
[^8]: 最長60分ですが、2021年3月末までは最長24時間となっています。
[^9]: 部屋（会議）のURLは使い回せるので、通話終了後リロードするだけで新しい通話になります。
[^10]: このような使い方について規約では言及されていませんが、利用したいときだけの通話に留めましょう。

## Google Meetの自動化

ここでは、ヘッドレスChromeをNode.jsで操作するためのライブラリPuppeteerを使って、Google Meetを自動化していきます。

### Googleへのログイン

Puppeteerで自動操作しているブラウザでGoogleにログインしようとすると、図2のようなメッセージが出てログインできない場合があります。

![ログインできない場合がある](/images/2023-11-25/login.png)
<br />▲図2 ログインできない場合がある

実は、自動化が制限されるのはログインだけなので、ログイン済みセッションのCookieをPuppeteerにインポートすることでGoogleの各サービスを利用できるようになります。
事前に「Edit This Cookie[^11]」や拙作の「Copy Cookies[^12]」といったChrome拡張でCookieをjson形式でエクスポートし、リスト1のようにPuppeteerにインポートします。

▼リスト1 Puppeteerの起動とCookieのインポート
```javascript
// puppeteerでブラウザを起動
const browser = await puppeteer.launch({
    args: ['--use-fake-ui-for-media-stream'],    // カメラ起動の許可をスキップ
    executablePath: '/usr/bin/chromium-browser', // Raspberry Pi OSのchromiumを使用
});

// 操作対象のページを作成
const page = await browser.newPage();

// jsonファイルからCookieをインポート
const cookies = JSON.parse(fs.readFileSync('~/cookies.json', 'utf-8'));
await page.setCookie(...cookies);
```

頑張ればCookieをエクスポートする操作も自動化もできますが、詳細は筆者のWebサイト[^13]をご覧ください。

[^11]: [Edit This Cookie](https://www.editthiscookie.com/)
[^12]: [Copy Cookies](https://chrome.google.com/webstore/detail/copy-cookies/jcbpglbplpblnagieibnemmkiamekcdg)
[^13]: [GoogleのサービスをPuppeteerで自動操作する方法 - ログイン編](http://makiuchi-d.github.io/2020/12/03/autologin-to-google.ja.html)

### 通話の開始

Google Meetでは一度作成した部屋（会議）のURLは何度でも使えます。
なので、事前に手動で作成した部屋のURLにアクセスして「今すぐ参加」ボタンを押すことで通話を開始できます。

Puppeteerでボタンを押すには、ボタンのDOM要素を`Page`内から探し`click()`することで簡単にできます。
要素の検索にはセレクタやXPathが利用できますが、Google MeetのHTMLはリスト2のようになっています。

▼リスト2 「今すぐ参加」ボタンのHTML
```html
<div role="button" class="uArJ5e UQuaGc Y5sE8d uyXBBb xKiqt RDPZE" jscontroller="VXdfxd"
    jsaction="click:cOuCgd; mousedown:UX7yZ; mouseup:lbsD7e; mouseenter:tfO1Yc;
    mouseleave:JywGue;touchstart:p6p2H; touchmove:FwuNnf;
    touchend:yfqBxc(preventMouseEvents=true|preventDefault=true);
    touchcancel:JMtRjd;focus:AHmuwe; blur:O22p3e; contextmenu:mg9Pef;" jsshadow
    jsname="Qx7uuf" aria-disabled="true" tabindex="-1" >
  <div class="Fvio9d MbhUzd" jsname="ksKsZd"></div>
  <div class="e19J0b CeoRYc"></div>
  <span jsslot class="l4V7wb Fxmcue">
    <span class="NPEfkd RveJvd snByac">今すぐ参加</span>
  </span>
</div>
```

このようにクラス名などが明らかに自動生成されたものなので、
意味的に要素を特定することが難しく、また頻繁に変更される可能性もあります。
セレクタによる要素の検索はやめたほうがよいでしょう。

一方で、ユーザに見せる文字列が変更されることはあまりないと考えられるので[^14]、
XPathを使って検索するのがよさそうです。

[^14]: 変更されることもあります。実際「ミーティング」が「通話」に変更されて動かなくなりました。

▼リスト3 通話の開始
```javascript
// 部屋のURLに移動
await page.goto('https://meet.google.com/your-meet-code');

// 「今すぐ参加」ボタンが現れるのを待つ
const button = await page.waitForXPath(
    '//span[text()="今すぐ参加"]', {'visible': true});

// ボタンをクリック（button.click()が動かない場合があるのでevaluateする）
await button.evaluate(node => node.click());
```

通話を開始できたらURLを添えてLINEやSlackなどに通知しておくと、スマートフォンなどから通話に参加するときに便利です。

### 参加の承諾（拒否）

他のユーザが通話に参加しようとしたとき、部屋のオーナーの画面には参加リクエストダイアログが表示されます。
ここで「承諾」ボタンを押してはじめて、そのユーザは通話に参加できるようになり、映像が見れるようになります。

この操作を自動化するには、`waitForXPath()`でダイアログが表示されるのを監視し、
表示されたダイアログの「承諾」または「拒否」ボタンを`click()`するという流れになります。
具体的には、`allowuser`のようなループを非同期に動かしておくことになります。

▼リスト4 自動で参加承諾する
```javascript
const sleep = msec => new Promise(resolve => setTimeout(resolve, msec));

while (true) {
    // 参加リクエストダイアログが現れるのを無限に待つ
    const dialog = await page.waitForXPath(
        '//div[@aria-label="この通話への参加をリクエストしているユーザーがいます"]',
        {'visible': true, 'timeout': 0});

    // ユーザ名とアイコン画像URLを取得
    const user = await (page.$x('img[@title]'))[0];
    const name = await (await user.getProperty('title')).jsonValue();
    const image = await (await user.getProperty('src')).jsonValue();

    // ここでユーザを確認

    // 許諾ボタンをクリック（"拒否"する場合も同様）
    const button = (await dialog.$x('//span[text()="承諾"]'))[0];
    await button.evaluate(node => node.click();

    // clickが処理されるのを待ってからダイアログを消す
    sleep(1000);
    await dialog.evaluate(node => node.parentNode.removeChild(node));
}
```

リスト4では省略しましたが、知らない人が入ってこないようにユーザを確認する必要があります。
ユーザ名だけでは同姓同名の人を識別できないので、アイコン画像のURLも使ってチェックするとよいでしょう。
ユニークな画像をアイコンにしていれば一意に識別できるはずです。

あらかじめユーザ名とアイコン画像URLのホワイトリストを作ってチェックすることで、
たとえ部屋のURLが漏れたとしても他人が参加することを防げます。
また、ここでもLINEやSlackに承諾・拒否したことを通知しておくとさらに安心です。

## ペットカメラの拡張

ここまでで最低限のペットカメラとして使えるようになりました。
せっかくなのでもうちょっとRaspberry Piらしい拡張をしたいと思います。

### スマートリモコンの実装

たとえば外泊するときなど、ペットの部屋の照明やエアコンを外から操作したくなります。
市販されているスマートリモコンを使っても解決できますが、
どうせならこのRaspberry Piペットカメラにスマートリモコン機能を加えてみたいと思います。

スマートリモコンの基板は、Qiitaの「格安スマートリモコンの作り方[^15]」を、
GPIO13で制御することと赤外線LEDを3並列にすること以外はそのまま実装しました。
また、リモコンの信号も学習させてコマンドラインから点灯・消灯できるようにしました。

[^15]: [格安スマートリモコンの作り方](https://qiita.com/takjg/items/e6b8af53421be54b62c9)

余談ですが、筆者の環境のRaspberry Pi 3BとRaspberry Pi OS 10の組み合わせでは、
なぜか`irrp.py`のplaybackが1/2倍速になってしまいました。
この現象はpigpioのIssue #331[^16]に報告されており、
`pigpiod`起動時に`-t0`オプションを加えることで解消できました。

[^16]: [pigpio Issue #331](https://github.com/joan2937/pigpio/issues/331)

### チャットでコマンド実行

Google Meetにはチャットもついており、外からメッセージを投げるにはちょうど良さそうです。
チャットメッセージが届いたときに表示されるポップアップの要素を取得できればよいのですが、
例によってクラス名などで識別することができません。

そこでリスト5のように、あらかじめコマンドにしたい文字列を含めたXPathでポップアップを待ち受けることにしました。
チャットメッセージからコマンド文字列を取得できたら、定義しておいた外部コマンドを子プロセスとして実行します。

基本的にどんなコマンドでも登録できるので、リモコンだけでなく汎用的に使うことができます。

▼リスト5 チャットでコマンドを実行
```javascript
// 実行したいコマンドを定義しておく
const commands = {
    '点灯': 'python3 irrp.py -p -g13 -f codes light:on',
    '消灯': 'python3 irrp.py -p -g13 -f codes light:off'
};

// コマンド文字列を含む要素を待ち受けるXPathを構築
const cmdxpath = '//div[@role="button"]/span[@jsslot]/span/div/div[{}]'.replace(
    '{}', Object.keys(commands).map(s => `text()="${s}"`).join(" or "));

while (true) {
    // コマンドの書かれたチャットダイアログを待ち受ける
    const msg = await page.waitForXPath(cmdxpath, {'visible': true, 'timeout': 0});

    // コマンド文字列を取り出す
    const cmd = await (await msg.getProperty('innerText')).jsonValue();

    // 外部コマンドの実行
    child_process.spawnSync('bash', ['-c', commands[cmd]]);

    // 何度も実行されないように要素を削除
    await msg.evaluate(node => node.parentNode.removeChild(node));
}
```

## 起動の自動化

最後に、Raspberry Pi起動時に今回紹介したPuppeteerのスクリプトを自動起動するようにしたいと思います。
やることは単純で、自動GUIログインを有効にしてAutostartにコマンドを登録するだけです。

Raspberry Pi OS 10の場合、`raspi-config`コマンドで「`1 System Options`」→「`S5 Boot / Auto Login`」と進み、
「`B4 Desktop Autologin`」を選択すると、起動時に`pi`ユーザとしてログインした状態でGUIが立ち上がります。

Autostartの登録は`/home/pi/.config/lxsession/LXDE-pi/autostart`ファイルにコマンドを書くだけです。
初期状態ではこのファイルが無いので、`/etc/xdg/lxsession/LXDE-pi/autostart`をコピーしてきます。
たとえば今回のスクリプトを`/home/pi/automeet.js`とした場合、リスト6のようにします。

▼リスト6 autostartファイル
```shell
@lxpanel --profile LXDE-pi
@pcmanfm --desktop --profile LXDE-pi
@xscreensaver -no-splash
node /home/pi/automeet.js
```

## まとめ

Raspberry Piを使い、Google MeetをPuppeteerで自動操作することでペットカメラにする方法を紹介しました。

スマートリモコン機能だけでなく、アイディア次第で色々な拡張ができるのもRaspberry Piのいいところですね。
みなさんも余っているRaspberry Piの活用方法として試してみてはいかがでしょう。

最後に、犬派猫派は排他の関係ではないことを強く主張しておきます。

--------
