---
layout: post
title: "Goで子プロセスを確実にKillする方法"
---

Goで子プロセスとして外部コマンドを呼び出すには、標準パッケージの`os/exec`を使えば簡単にできます。
`exec.Command()`で作った子プロセスを途中でKillするために、`(*Cmd) Process.Kill()`も用意されています。

ただしこの関数を使うときは気をつけないと、孤児プロセスを生んでしまいます。

ここでは、孤児プロセスを生まないように安全に子プロセスをKillする方法を紹介します。

※手元の実行環境はLinuxですが、macOSもPOSIXなのできっと同じです。Windowsは知りません。

## 孤児プロセスを生む状況の再現

子プロセス役として、単純に`sleep`コマンドを呼び出すだけのプログラムを用意します。
これを`execsleep`というコマンドとしてビルドしておきます。

```Go:execsleep.go
package main

import "os/exec"

func main() {
	exec.Command("sleep", "100").Run()
}
```

続いて親プロセス役として、上で作った`execsleep`を呼び出すプログラムを用意します。
`exec.Command()`と`cmd.Start()`で子プロセスを起動し、5秒後に`cmd.Process.Kill()`でKillしています。
さらに、子プロセスを起動したときとKillしたときのプロセス一覧を`ps`コマンドで表示するようにしておきます。
これを`parent`というコマンドとしてビルドします。

```Go:parent.go
package main

import (
	"fmt"
	"os/exec"
	"time"
)

func showPS() {
	b, err := exec.Command("ps", "j").Output()
	fmt.Println(string(b), err)
}

func main() {
	cmd := exec.Command("./execsleep")
	cmd.Start()
	fmt.Println("process start", cmd.Process.Pid)
	time.Sleep(time.Second)
	showPS()

	go func() {
		err := cmd.Wait()
		fmt.Println("process done:", err)
	}()

	t := time.NewTimer(5 * time.Second)
	<-t.C
	fmt.Println("process kill")
	cmd.Process.Kill()

	time.Sleep(time.Second)
	showPS()
}
```

実行結果は次のようになります。

```shell-session
makki@VJS112$ ./parent 
process start 22744
   PPID     PID    PGID     SID TTY        TPGID STAT   UID   TIME COMMAND
   7700    7707    7707    7707 pts/2      22739 Ss    1000   0:02 /bin/bash
   7707   22739   22739    7707 pts/2      22739 SLl+  1000   0:00 ./parent
  22739   22744   22739    7707 pts/2      22739 SLl+  1000   0:00 ./execsleep
  22744   22749   22739    7707 pts/2      22739 S+    1000   0:00 sleep 100
  22739   22750   22739    7707 pts/2      22739 R+    1000   0:00 ps j
 <nil>
process kill
process done: signal: killed
   PPID     PID    PGID     SID TTY        TPGID STAT   UID   TIME COMMAND
   7700    7707    7707    7707 pts/2      22739 Ss    1000   0:02 /bin/bash
   7707   22739   22739    7707 pts/2      22739 SLl+  1000   0:00 ./parent
      1   22749   22739    7707 pts/2      22739 S+    1000   0:00 sleep 100
  22739   22753   22739    7707 pts/2      22739 R+    1000   0:00 ps j
 <nil>
```

`./execsleep`はKillされたことでプロセス一覧から消えていますが、
その子プロセスの`sleep 100`は孤児プロセスとなり、親プロセスID(PPID)=1としてinitに引き取られて残ってしまいました。

## 孫プロセスまでまとめてKillする

軽くググると[解決策](https://medium.com/@felixge/killing-a-child-process-and-all-of-its-children-in-go-54079af94773)が見つかりました。
（`exec.CommandContext()`というものもありますが、これはcontext終了時に`cmd.Process.Kill()`しているだけなので無力です）


通常、子プロセスは親プロセスと同じプロセスグループID(PGID)を持ちますが、
`cmd.SysProcAAttr.Setpgid`を`true`にすることで、
子プロセス生成時に`setpgid`システムコールが呼ばれて、新たなPGIDが割り当てられます（子プロセスのPIDと同じ値になります）。
すると子プロセスと孫プロセスのPGIDは、この新たに割り当てられたPGIDになります。

そして、`syscall.Kill(pid, sig)`の`pid`を負の値にすることで、PGIDが`-pid`のすべてのプロセス、つまりプロセスグループに対してシグナルを送ることができます。
これは`kill`システムコールの挙動です。

この方法でparent.goのKillを置き換えると次のようになります。

```Go:parent.go.diff
func main() {
	cmd := exec.Command("./execsleep")
+	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Start()
	fmt.Println("process start", cmd.Process.Pid)
	time.Sleep(time.Second)
	showPS()

	go func() {
		err := cmd.Wait()
		fmt.Println("process done:", err)
	}()

	t := time.NewTimer(5 * time.Second)
	<-t.C
	fmt.Println("process kill")
-	cmd.Process.Kill()
+	syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) // setpgidしたPGIDはPIDと等しい

	time.Sleep(time.Second)
	showPS()
}
```

実行結果は次のようになります。

```sell-session
makki@VJS112$ ./parent 
process start 37746
   PPID     PID    PGID     SID TTY        TPGID STAT   UID   TIME COMMAND
   7700    7707    7707    7707 pts/2      37742 Ss    1000   0:02 /bin/bash
   7707   37742   37742    7707 pts/2      37742 SLl+  1000   0:00 ./parent
  37742   37746   37746    7707 pts/2      37742 SLl   1000   0:00 ./execsleep
  37746   37751   37746    7707 pts/2      37742 S     1000   0:00 sleep 100
  37742   37752   37742    7707 pts/2      37742 R+    1000   0:00 ps j
 <nil>
process kill
process done: signal: killed
   PPID     PID    PGID     SID TTY        TPGID STAT   UID   TIME COMMAND
   7700    7707    7707    7707 pts/2      37742 Ss    1000   0:02 /bin/bash
   7707   37742   37742    7707 pts/2      37742 SLl+  1000   0:00 ./parent
  37742   37754   37742    7707 pts/2      37742 R+    1000   0:00 ps j
 <nil>
```

確かに`sleep`もKillされるようになりました。

ただしこの方法だと困ったことが起こります。
子プロセスがKillされる前に親プロセスを`Ctrl+C`で止めると次のようになります。

```shell-session
makki@VJS112:$ ./parent 
process start 38218
   PPID     PID    PGID     SID TTY        TPGID STAT   UID   TIME COMMAND
   7700    7707    7707    7707 pts/2      38213 Ss    1000   0:02 /bin/bash
   7707   38213   38213    7707 pts/2      38213 SLl+  1000   0:00 ./parent
  38213   38218   38218    7707 pts/2      38213 SLl   1000   0:00 ./execsleep
  38218   38223   38218    7707 pts/2      38213 S     1000   0:00 sleep 100
  38213   38224   38213    7707 pts/2      38213 R+    1000   0:00 ps j
 <nil>
^C
makki@VJS112:$ ps j
   PPID     PID    PGID     SID TTY        TPGID STAT   UID   TIME COMMAND
   7700    7707    7707    7707 pts/2      38240 Ss    1000   0:02 /bin/bash
      1   38218   38218    7707 pts/2      38240 SLl   1000   0:00 ./execsleep
  38218   38223   38218    7707 pts/2      38240 S     1000   0:00 sleep 100
   7707   38240   38240    7707 pts/2      38240 R+    1000   0:00 ps j
```

`./execsleep`と`sleep`が残ってしまいました。


`Ctrl+C`を入力すると、端末はフォアグラウンドのプロセスグループにに対して`SIGINT`を送信します。
このプログラムでは`./execsleep`を`setpgid`することで別のプロセスグループにしているため、`Ctrl+C`によるシグナルが届かなくなってしまっています。

これに対処するには、シグナルを受け取ったときに子プロセスをきちんと処理するように、親プロセス側でシグナルハンドラを実装してあげる必要があります。

## シグナル受信時にも子プロセスを処理する

Goでシグナルを扱うには、標準パッケージの`os/signal`が便利です。
`signal.Notify(c, sig ...)`で受信したいシグナル種別を設定したら、チャネル`c`にシグナルが流れてきます。

ここではSIGHUP、SIGINT、SIGTERMを受け取ったときにタイマーを待たずにKillの処理に移るという実装をしてみました。

```Go:parent.go.diff
func main() {
	cmd := exec.Command("./execsleep")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Start()
	fmt.Println("process start", cmd.Process.Pid)
	time.Sleep(time.Second)
	showPS()

	go func() {
		err := cmd.Wait()
		fmt.Println("process done:", err)
	}()

	t := time.NewTimer(5 * time.Second)
-	<-t.C
+	s := make(chan os.Signal)
+	signal.Notify(s, syscall.SIGHUP, syscall.SIGINT, syscall.SIGTERM)
+	select {
+	case sig := <-s:
+		fmt.Println("signal:", sig)
+	case <-t.C:
+		fmt.Println("timer")
+	}
	fmt.Println("process kill")
	syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) // setpgidしたPGIDはPIDと等しい

	time.Sleep(time.Second)
	showPS()
}
```

5秒経過の場合とCtrl+Cで止めた場合の、それぞれの結果は次のようになります。

```shell-session
makki@VJS112$ ./parent 
process start 45444
   PPID     PID    PGID     SID TTY        TPGID STAT   UID   TIME COMMAND
   7700    7707    7707    7707 pts/2      45440 Ss    1000   0:02 /bin/bash
   7707   45440   45440    7707 pts/2      45440 SLl+  1000   0:00 ./parent
  45440   45444   45444    7707 pts/2      45440 SLl   1000   0:00 ./execsleep
  45444   45449   45444    7707 pts/2      45440 S     1000   0:00 sleep 100
  45440   45452   45440    7707 pts/2      45440 R+    1000   0:00 ps j
 <nil>
timer
process kill
process done: signal: killed
   PPID     PID    PGID     SID TTY        TPGID STAT   UID   TIME COMMAND
   7700    7707    7707    7707 pts/2      45440 Ss    1000   0:02 /bin/bash
   7707   45440   45440    7707 pts/2      45440 SLl+  1000   0:00 ./parent
  45440   45459   45440    7707 pts/2      45440 R+    1000   0:00 ps j
 <nil>
```

```sell-session
makki@VJS112$ ./parent 
process start 45479
   PPID     PID    PGID     SID TTY        TPGID STAT   UID   TIME COMMAND
   7700    7707    7707    7707 pts/2      45474 Ss    1000   0:02 /bin/bash
   7707   45474   45474    7707 pts/2      45474 SLl+  1000   0:00 ./parent
  45474   45479   45479    7707 pts/2      45474 SLl   1000   0:00 ./execsleep
  45479   45484   45479    7707 pts/2      45474 S     1000   0:00 sleep 100
  45474   45485   45474    7707 pts/2      45474 R+    1000   0:00 ps j
 <nil>
^Csignal: interrupt
process kill
process done: signal: killed
   PPID     PID    PGID     SID TTY        TPGID STAT   UID   TIME COMMAND
   7700    7707    7707    7707 pts/2      45474 Ss    1000   0:02 /bin/bash
   7707   45474   45474    7707 pts/2      45474 SLl+  1000   0:00 ./parent
  45474   45490   45474    7707 pts/2      45474 R+    1000   0:00 ps j
 <nil>
```

どちらも孫プロセスまで含めてきれいに処理できています。
（まあ同じ処理に行き着くので……）

## まとめ

Goの`os/exec`パッケージはかなり低水準なライブラリなので、利用者側でいろいろハンドリングしてあげる必要があります。

よくよく調べるとrealizeやfreshを含め、goのタスクランナーのほとんどが孤児プロセスを生む問題を抱えたままです。
拙作のタスクランナー・ホットリロードツール[arelo](https://github.com/makiuchi-d/arelo)でも同じようにこの問題にハマり、
ここで紹介したような対策を施しました。

Goで外部コマンドを呼び出すときは気をつけましょう。
