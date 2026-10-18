# 楽天ブックスの購入リンク

Amazon向け購入ボタンを楽天アフィリエイトへ置き換えた。ホーム・検索・マイページで同じ書籍詳細ボタンを使用する。

## 有効化
1. 楽天アフィリエイトで公開サイトの登録・必要な手続きを行い、自分のアフィリエイトIDを取得する。
2. Cloudflare本番用はGitHubの`production` Environment Secretsに`RAKUTEN_AFFILIATE_ID`を登録し、デプロイ時にWorker Secretへ設定する。Vercelステージング/手動ロールバックに必要なRuntime Variablesは別途維持する。楽天APIのアプリIDやアクセスキーとは別の値。
3. GitHub Actionsから新しくデプロイする。既存の `RAKUTEN_APP_ID` / `RAKUTEN_ACCESS_KEY` は維持する。GitHubの `AMAZON_ASSOCIATE_TAG` は不要。
4. 書籍詳細で「楽天ブックスで購入する」と広告表記を確認し、リンクが該当の本を指すことを確認する。動作確認目的の自己購入はしない。

## 動作
- サーバーだけがaffiliateIdを指定し、公式APIのaffiliateUrlをそのまま使用する。クライアントからIDを上書きできない。
- 本棚などの既存データはISBN完全一致で楽天ブックスの商品を照合する。タイトルによる曖昧検索やAmazonへの誘導はしない。
- HTTPSの楽天アフィリエイトURLかつ楽天ブックスの商品ページを指すリンクのみ表示する。
- ID未設定・該当商品なし・通信失敗時は購入ボタンを非表示にし、通常の閲覧や投稿を妨げない。
- 価格・在庫・報酬の確定額は表示しない。リンク先で確認する。

公式仕様: https://webservice.rakuten.co.jp/documentation/books-book-search
洋書: https://webservice.rakuten.co.jp/documentation/books-foreign-search
