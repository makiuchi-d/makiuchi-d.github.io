---
layout: post
title: "SQLを含めたユニットテストにgo-mysql-serverが便利"
---

[go-mysql-server](https://github.com/dolthub/go-mysql-server)は、ピュアGoで書かれたMySQL互換のインメモリDBです。
[README](https://github.com/dolthub/go-mysql-server/blob/main/README.md#using-the-in-memory-test-server)にあるようにサーバとして起動することもできますが、
[`database/sql/driver`](https://pkg.go.dev/database/sql/driver)の[`Driver`](https://pkg.go.dev/database/sql/driver#Driver)も用意されているので、プロセス内で完結することもできます。

このインメモリDBをいろいろなORMと組み合わせてユニットテストで使う方法を紹介します。

- [sqlc](#sqlc)
- [sqlx](#sqlx)
- [GORM](#gorm)
- [ent](#ent)

## go-mysql-server/driverの使い方

サンプル実装を用意したのであわせてご覧ください。
- [https://github.com/makiuchi-d/testdb](https://github.com/makiuchi-d/testdb)

<p style="background-color:bisque;border-left:0.3em solid orange;padding:0.5em">
<strong>⚠</strong>
現在の最新リリース(0.16.0)にはDriverにいくつかバグがあります。
修正PRはすでに取り込まれているので、 <code>go get</code> 時にはlatestではなくHEADを指定して下さい。
修正済みバージョンのリリースは10〜11月頃だと思われます。
</p>

よくあるDriverと違い `go-mysql-server` はDriverの登録はしてくれないので、自分で [`sql.Register()`](https://pkg.go.dev/database/sql#Register) を呼ぶ必要があります。

[公式の例](https://github.com/dolthub/go-mysql-server/blob/main/driver/_example/create.go) を参考に、サンプルでは次のように `factory` を定義してRegisterしました。

```go
func init() {
	sql.Register("sqle", driver.New(factory{}, nil))
}

type factory struct{}

func (f factory) Resolve(dbName string, options *driver.Options) (string, sqle.DatabaseProvider, error) {
	memdb := memory.NewDatabase(dbName)
	memdb.EnablePrimaryKeyIndexes()
	provider := memory.NewDBProvider(
		memdb,
		information_schema.NewInformationSchemaDatabase(),
	)
	return name, provider, nil
}
```

`Register` で登録したら他のDBと同じように [`sql.Open()`](https://pkg.go.dev/database/sql#Open) で開けるようになります。

```go
db, err := sql.Open("sqle", "mytestdb")
```

`sql.Open` の引数のドライバの指定は、Registerした `"sqle"` を指定し、`dataSourceName`（DSN）に使いたい論理DB名を書きます。

DSNは `factory.Resolve` の `dbName` にそのまま渡されるので、その名前のインメモリDBを `memory.NewDatabase()` で作成します。
ここで `memdb.EnablePrimaryKeyIndexes()` をしておかないと `FORGIGN KEY` を指定するときにエラーになるので忘れずに有効化します。

このDBととInformationSchemaの2つの論理DBをもつインスタンスを `memory.NewDBProvider()` で作成して返却します。
もし論理DBを複数利用したい時はそれぞれ `memory.NewDatabase()` して `memory.NewDBProvider()` の引数に加えれば良いです。

こうして作られたDBが `sql.Open()` から `*sql.DB` 型として返ってきます。
この時点ではまだ論理DBが選択されていない状態なので、最初に`db.Exec`で`USE`文を実行すると便利です。

サンプル実装では次のように `testdb.New(dbName)` を定義しています。

```go
func New(dbName string) *sql.DB {
	db := Must1(sql.Open("sqle", dbName))
	Must1(db.Exec("USE " + dbName))
	return db
}
```

## ORMと組み合わせた利用

ここではDBの初期化部分を抜粋して説明します。
完全なコードは[サンプル実装](https://github.com/makiuchi-d/testdb/)のテストコードをご覧ください。


### [sqlc](https://sqlc.dev/)

[サンプル実装](https://github.com/makiuchi-d/testdb/blob/main/example-sqlc/main_test.go)

```go
db := testdb.New("testdb")
query := sqlc.New(db)
```

go-mysql-serverはMySQL互換なので、`sqlc.yaml` で `engine: "mysql"` を指定してコード生成します。


sqlcでは `*sql.DB` を `New()` にそのまま渡すだけなので、とくに難しいことはなく `testdb.New()` の返り値をそのまま使えます。


### [sqlx](https://github.com/jmoiron/sqlx)

[サンプル実装](https://github.com/makiuchi-d/testdb/blob/main/example-sqlx/main_test.go)

```go
db := testdb.New("testdb")
dbx := sqlx.NewDb(db, "mysql")
```

sqlxは `driverName` によって挙動が変わるようになっているため、 `"mysql"` というドライバ名を指定する必要があります。
このため、 [`sqlx.Open()`](https://pkg.go.dev/github.com/jmoiron/sqlx#Open) ではなく、[`sqlx.NewDB()`](https://pkg.go.dev/github.com/jmoiron/sqlx#NewDb) を使います。

### [GORM](https://gorm.io/)

[サンプル実装](https://github.com/makiuchi-d/testdb/blob/main/example-gorm/main_test.go)

```
db := testdb.New("testdb")
gormDB, err := gorm.Open(mysql.New(mysql.Config{
	Conn: db,
}), &gorm.Config{})
```

GORMでは `gorm.io/driver/mysql` を使います。
`mysql.Config` の `DriverName`、`DSN` を指定してOpenすることもできますが、最初にUSE文でのDBを選択しないといけないので、
先程定義した `testdb.New()` を使ったほうが便利かもしれません。
この場合、ドキュメントの [既存データベース接続](https://gorm.io/docs/connecting_to_the_database.html#Existing-database-connection) にあるように
`mysql.Config` の `Conn` に `*sql.DB` を設定します。

### [ent](https://entgo.io/)

[サンプル実装](https://github.com/makiuchi-d/testdb/blob/main/example-ent/main_test.go)

```
db := testdb.New("testdb")
drv := entsql.OpenDB("mysql", db)
client := enttest.NewClient(t, enttest.WithOptions(ent.Driver(drv)))
```

entは独自に定義した `"sqle"` というドライバには対応していないため、そのままでは `Open()` できません。
ですが [sql.DBを利用する方法](https://entgo.io/docs/sql-integration/) にあるとおり、
`OpenDB()` でドライバ作ることでMySQL互換DBとして利用できます。

またこの例のように、ユニットテスト用に自動マイグレーションしてくれる `enttest` の利用もできます。

## DBとユニットテストについて

DBの絡むロジックのユニットテストで悩んだ経験のある人も多いことでしょう。

リポジトリパターンなどでDBへのアクセスを分離して、ユニットテストではリポジトリをモックに置き換えるのはよく知られた手法です。
しかし実際のSQLを含めたリポジトリクラス自体のテストはどこかでやらなければならず、問題の先送りでしかありませんでした。

また[sqlmock](https://github.com/DATA-DOG/go-sqlmock)など、DBの振る舞い自体をモックにするものもあります。
このようなモックでは、どのようなSQLがどの順序で発行されるかに依存したテストを書くことになり、
SQL自体の変更に対応できない壊れやすいテストになってしまいます。

ユニットテストでも本物のDBを使う方法ももちろんあります。
ただ別途立てるサーバはテストのプロセス外依存になってしまい、実行環境次第で動かなくなる安定性の問題があります。
この点はDockerなどのコンテナでだいぶ解消しますが、テストの仕組みがやや大掛かりになります。
また、サーバの起動に時間がかかるのも問題です。

テストプログラムと同じプロセスの中で動くインメモリDBなら他のプロセスやファイルシステムへの依存もなくなり安定します。
これまでプロセス内で動くインメモリDBといえば[SQLite](https://www.sqlite.org/index.html)が定番でした。
しかし、SQL方言の問題やRDBMS固有の機能が使えないため、ユニットテストだけSQLiteを使うというのはあまり現実的ではありません。

そこでgo-mysql-serverの出番です。
MySQL互換を謳っているため、MySQL固有の機能を使っていても同じように動くことが期待できます。
さらにこの記事で紹介したように、driverを使えば単一プロセス内で完結します。

一方で問題点として、トランザクションに対応していなかったり、他にも非互換が残っている可能性はもちろんあります。
e2eテストのような複雑なシナリオでは、やはり本物のMySQLを使うのがよいでしょう。
とはいえ、小さいロジック単位のユニットテストならgo-mysql-serverでも十分事足りますし、
なによりプロセス外依存がなく、どんな環境でもすばやく確実にテストを実行できるようになります。


## おわりに

MySQL互換インメモリDBのgo-mysql-serverを、サーバを立てずにプロセス内のみで、ORMと組み合わせて使う方法を紹介しました。
本番でMySQLを使っているなら、SQLを含むロジックそのままに、プロセス外依存のない安定したテストができるようになります。
ユニットテストのお供にいかがでしょうか。
