---
layout: post
title: "LUKS暗号化パーティションにUbuntuをインストール（LVMなし版）"
---

Ubuntuのインストールディスクを暗号化するには、dm-crypt+LUKSのを利用することができます。
標準でインストーラが対応しているため、
インストール先を選ぶときに「暗号化LVMをセットアップ」にチェックを入れるだけで手軽に暗号化できます。

![暗号化LVMをセットアップ](/images/2020-05-05/crypt-lvm-setup.png)

ただ、この方法ではパーティション構成を自由に設定することができません。
EFIシステムパーティションや`/boot`パーティションが大きめに取られますし、
LVMのレイヤーが強制的に挟まり、SWAPパーティションも作られてしまいます。

```shell-session
kubuntu@kubuntu:~$ lsblk
NAME                   MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINT
nvme0n1                259:0    0   477G  0 disk  
├─nvme0n1p1            259:1    0   512M  0 part  /boot/efi
├─nvme0n1p2            259:2    0   732M  0 part  /boot
└─nvme0n1p3            259:3    0 475.7G  0 part  
  └─nvme0n1p3_crypt    253:0    0 475.7G  0 crypt 
    ├─vgkubuntu-root   253:1    0 474.8G  0 lvm   /
    └─vgkubuntu-swap_1 253:2    0   980M  0 lvm   [SWAP]
```

ここでは、VAIO S11（VJS112）に自由なパーティション構成の暗号化ディスクにKubuntuをインストールする手順を書き残しておきます。
なおKubuntuで行っていますが、Ubuntuでも基本的に同じです。

## パーティションの構成

UEFIでブートする構成です。このためMBRではなくGPTです。
KDEのパーティションマネージャを使いましたが、最終的に次の3つのパーティションが作られればどんな方法でもかまいません。

![最終的なパーティション構成](/images/2020-05-05/final-partitions.png)

### EFIシステムパーティション（ESP） `/dev/nvme0n1p1`

ESPはFAT32でフォーマットされます。
KDEのパーティションマネージャで作成できるFAT32の最小サイズは32MiBですが、このサイズではESPは正しく動かないようです。
いくつか試したところ、33MiBが手元では最小のようです。
（インストーラでESPを作成すると35MBより大きいサイズを求められ、36MBを指定するとパーティションマネージャの33MiBと同じサイズになりました）

GRUBのUEFIアプリケーションは8MB程度なので、他のOSと共存しないのであれば最小サイズでも十分です。

### `/boot`パーティション `/dev/nvme0n1p2`

起動時に暗号を解除するのはカーネルの役目です。
このため、ブートローダ、カーネル、initramfsのイメージは暗号化することはできません。
これらは`/boot`ディレクトリ以下に置かれるため、暗号化しないパーティションとして分けておきます。
aptでカーネルをアップデートする時に最低3世代分のカーネルやinitramfsなどが置かれるので、それを見越して余裕を持ったサイズが必要です。
最近のUbuntuでは1世代あたり100MB程度消費するので、最低でも400MBは確保しておかないとカーネルがアップデートできなくなります。

### 暗号化パーティション `/dev/nvme0n1p3`

暗号化パーティションを作成します。
パーティションマネージャでは「Encrypt with LUKS」のチェックを入れてパスワードを設定するだけで作成できます。
LVMは不要なので、直接ext4などのファイルシステムを指定します。

![暗号化パーティションの作成](/images/2020-05-05/new-partition.png)

パーティションマネージャで暗号化パーティションを作成すると、`/dev/mapper`以下のデバイス名がUUIDを含む長い名前になってしまうので、
一旦、`cryptsetup luksClose`でマッピングを解除して、`lucksOpen`しなおして名前をつけなおします。
ここでは`kubuntu`としておきます。

```shell-session
kubuntu@kubuntu:~$ lsblk
NAME                                          MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINT
loop0                                           7:0    0   1.7G  1 loop  /rofs
sda                                             8:0    1   7.2G  0 disk  
├─sda1                                          8:1    1   2.2G  0 part  /cdrom
├─sda2                                          8:2    1   3.9M  0 part  
└─sda3                                          8:3    1     5G  0 part  /var/crash
nvme0n1                                       259:0    0   477G  0 disk  
├─nvme0n1p1                                   259:2    0    33M  0 part  
├─nvme0n1p2                                   259:3    0   500M  0 part  
└─nvme0n1p3                                   259:5    0 476.4G  0 part  
  └─luks-f89a008e-8348-4468-be36-1fe0828db162 253:0    0 476.4G  0 crypt 
kubuntu@kubuntu:~$ sudo cryptsetup luksClose luks-f89a008e-8348-4468-be36-1fe0828db162
kubuntu@kubuntu:~$ sudo cryptsetup luksOpen /dev/nvme0n1p3 kubuntu
Enter passphrase for /dev/nvme0n1p3: 
kubuntu@kubuntu:~$ lsblk
NAME        MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINT
loop0         7:0    0   1.7G  1 loop  /rofs
sda           8:0    1   7.2G  0 disk  
├─sda1        8:1    1   2.2G  0 part  /cdrom
├─sda2        8:2    1   3.9M  0 part  
└─sda3        8:3    1     5G  0 part  /var/crash
nvme0n1     259:0    0   477G  0 disk  
├─nvme0n1p1 259:2    0    33M  0 part  
├─nvme0n1p2 259:3    0   500M  0 part  
└─nvme0n1p3 259:5    0 476.4G  0 part  
  └─kubuntu 253:0    0 476.4G  0 crypt 
```

これで、`/dev/mapper/kubuntu`として暗号化されたパーティションにアクセスできるようになりました。

## Kubutuのインストール

パーティションの準備ができたので、通常通りインストーラを使ってKubuntuをインストールしていきます。

インストール先を選択するところで「手動」を選択し、先ほど作成したパーティションをそれぞれ割り振っていきます。
`/dev/nvme0n1p1`を「EFIシステムパーティション」に、`/dev/nvme0n1p2`のマウントポイントを`/boot`に設定します。
暗号化したい`/`（ルート）は、`nvme0n1p3`ではなく`/dev/mapper/kubuntu`に設定します。

ブートローダのインストール先は`/dev/nvme0n1`から変更しません。

![インストール先の選択](/images/2020-05-05/install-partition.png)

あとは普通にインストールを進めてユーザの設定などをしてしまいます。
ただ、まだやることがあるので最後に再起動はせずに試用を続けます。

## 起動時の暗号化解除の設定

ここまでで`/dev/mapper/kubuntu`にKubuntuをインストールしましたが、
インストーラはこのデバイスが暗号化されているか感知していないため、
インストーラの作成したinitramfsには暗号化解除の設定やツールは含まれません。

そこで、手動で`/etc/crypttab`を適切に設定したうえでinitramfsを再構築する必要があります。

インストーラの終了直後は`/target`にルートディレクトリのパーティションがマウントされた状態なので、
`/target/etc/crypttab`を作成して暗号化されたパーティションのUUIDとオプションを次のように書き込みます。
パーティションのUUIDは`blkid`コマンドなどで調べられます。

```shell-session
kubuntu@kubuntu:~$ blkid /dev/nvme0n1p3
/dev/nvme0n1p3: UUID="f89a008e-8348-4468-be36-1fe0828db162" TYPE="crypto_LUKS" PARTUUID="356cc4a4-ef90-954c-a30e-2659facfb1cc"
```

/etc/crypttab:
```
kubuntu UUID=f89a008e-8348-4468-be36-1fe0828db162 none luks,discard
```

initramfsを更新するためには、`/target`に`chroot`したうえで`update-initramfs`コマンドを叩きます。
このとき`/boot`パーティションなどを忘れずにマウントしておきます。

```
kubuntu@kubuntu:~$ sudo mount /dev/nvme0n1p2 /target/boot
kubuntu@kubuntu:~$ sudo mount /dev/nvme0n1p1 /target/boot/efi
kubuntu@kubuntu:~$ sudo mount -t proc none /target/proc
kubuntu@kubuntu:~$ sudo mount -o bind /dev /target/dev
kubuntu@kubuntu:~$ sudo mount -o bind /sys /target/sys
kubuntu@kubuntu:~$ sudo chroot /target
root@kubuntu:/# update-initramfs -u
update-initramfs: Generating /boot/initrd.img-5.4.0-28-generic
```

これで`/etc/crypttab`の情報をもとに暗号化解除の設定が含まれたinitramfsが作られました。

以上で設定は終わりです。
再起動すると、起動時にパスワードを聞かれるようになったはずです。
パスワードを入力すると暗号が解除され、Kubuntuが起動します。
