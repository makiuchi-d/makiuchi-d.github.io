---
layout: post
title: "GoogleのサービスをPuppeteerで自動操作する方法 - ログイン編"
---

Webサービスの自動操作には様々な手段がありますが、[Puppeteer](https://pptr.dev/)や[Selenium](https://www.selenium.dev/)といったブラウザ本体を自動操縦できるツールがとても便利です。
ところが、GoogleのサービスをPuppeteerやSeleniumで利用しようとした時、ログインフォームにアカウント情報を入力してもログインできないことがあります。

![ログインできない](/images/2020-12-03/login-failed.png)

この壁をどうにかするのがこの記事です。

_※Google検索は自動化ツールによるスクレイピングが禁止されています。他サービスも規約をよく確認して自己責任で実施してください。_

## 手動でログインしてCookieを流用する

実は自動操作できないのはログインだけです。
手動でログインしたセッションのCookieを保存しておき、Puppeteerで起動したブラウザにインポートしてからGoogleの各種サービスにアクセスすると普通に自動操作できます。

Cookieの保存方法はいくつかありますが、よく使われているのは[Edit This Cookie](http://www.editthiscookie.com/)というChrome拡張を利用する方法です。

Googleにログインした状態で「Cookieのエクスポート」ボタンを押すとクリップボードにCookie情報がJSON形式でコピーされます。
このJSONをファイルに保存しておき、次のようにPuppeteerの[`page.setCookie()`](https://pptr.dev/#?product=Puppeteer&version=v5.5.0&show=api-pagesetcookiecookies)で設定してあげればログイン済みのブラウザと同じ状態になります。

```javascript
const cookies = JSON.parse(fs.readFileSync('./cookies.json', 'utf-8'));
await page.setCookie(...cookies);
```

あとは通常通り使いたいサービスのURLに移動して操作するだけです。

## ログインも自動化したい

当然ログイン状態はいつか期限が切れるので、定期的にCookieのJSONを更新する必要があります。
手元のPCで動かすツールであれば更新するのも手間ではないと思います。
しかし、普段ログインしない機器で動かしている場合にはちょっと面倒です。

Googleにログインできないのは、Puppeteerでブラウザを自動操作しているからでした。
そこで、ブラウザ自体は普通に立ち上げ、キーボード入力を自動化するツールを使えばログインも自動化できそうです。
普段ログインしないのであれば、別のアプリにフォーカスが奪われて入力できないという事故も無いでしょう。

Edit This Cookieではエクスポートにマウス操作が必要だったので、キーボードショートカットだけで全く同様にCookieをエクスポートできるChrome拡張を自作しました。

[Copy Cookies](https://chrome.google.com/webstore/detail/copy-cookies/jcbpglbplpblnagieibnemmkiamekcdg) ([Github](https://github.com/makiuchi-d/copycookies))

`Ctrl+Shift+K`でクリップボードにCookie情報がコピーされるので、それをJSONファイルに書き出せば自動化完了です。

## ログイン自動化スクリプト

RaspberryPi（Raspberry Pi OS）上で自動ログインするために次のようなスクリプトを使っています。
キーボード入力の自動化には「xdotool」を、クリップボードの内容を取り出すのに「xsel」コマンドを使っています。
他のX window環境でも基本的に使えるはずです（sleep時間の調整は必要です）。
また、それ以外の環境でもキーボード入力やクリップボードアクセスのためのコマンドラインツールがあるはずなので、参考にしてみてください。

```bash
#!/bin/bash -ex
rm -f rm $HOME/.config/chromium/Default/Cookies

xdotool - <<-EOF
	exec --args 2 chromium-browser 'https://accounts.google.com/ServiceLogin'
	sleep 15
	getactivewindow
	type --args 1 "$ACCOUNT"
	sleep 1
	key Return
	sleep 3
	type --args 1 "$PASSWD"
	sleep 1
	key Return
	sleep 15
	key Ctrl+Shift+K
	sleep 1
	exec --args 3 bash -c 'xsel -o > cookies.json'
	windowkill
EOF
```

（クリップボードにアクセスせずにブラウザを終了するとなぜかクリップボードが空になってしまうので、xdotoolの中でxselしてからwindowkillしています。）

このスクリプトを実際に使って自宅のRaspberryPiでGoogleMeetを使ったペットカメラとして運用しているのですが、その話はまた別の機会に。
