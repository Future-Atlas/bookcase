# 楽天ブックスジャンルID連携と年齢制限の扱い

## データ取得

- 楽天ブックス書籍・洋書検索APIの書籍データには `booksGenreId` が含まれる。
- 1冊が複数のジャンルに属する場合、IDは `001004008/001021002` のように `/` 区切りで返る。
- `Book.rakutenGenreIds` に文字列の配列として保持し、先頭の `0` を失わない。
- `Book.belongsToRakutenGenre('001004')` は、`001004` と `001004008` のような下位ジャンルにも一致する。
- `Book.genre` は従来の検索カテゴリ名を維持するため変更しない。ジャンルIDとして使わない。

公式資料: https://webservice.rakuten.co.jp/documentation/books-book-search
ジャンル名と親子関係: https://webservice.rakuten.co.jp/documentation/books-genre-search

## 18歳未満の書籍フィルタへの接続

### 登録する場所

`lib/config/restricted_rakuten_genres.dart` の
`RestrictedRakutenGenres.verifiedAdultOnly` が唯一の登録台帳。
**登録前は空集合であり、根拠のないジャンルを自動で禁止しない。**

登録例（次のIDは**架空の例**であり、そのまま使わないこと）：

```dart
static const Map<String, String> verifiedAdultOnly = <String, String>{
  // '001999001': '正式な成人専用ジャンル名 / 2026-10-29 / https://公式根拠URL',
};
```

登録時にはIDのゼロを残し、**ジャンル名、確認日、根拠URL**を併記する。
下位ジャンルは自動的に対象になるため、`001`（すべての本）、
`005`（洋書全体）、`007`（雑誌全体）やBL/TL/一般コミック等の
広いジャンルを登録してはいけない。
監査には必ずジャンル名だけでなく、実際の所属書籍も確認する。

### ジャンル一覧の調査

1. GitHub Actions → **Audit Rakuten Books Genre Taxonomy** → Run workflow を開く。
2. `main` ブランチ、`root_genre_id=001`（国内書籍）、`max_nodes=300`などで実行する。
   洋書の確認には `005` を選択する。
3. 完了後、Actions実行画面のArtifactsから `rakuten-books-genre-audit` を取得する。
4. JSONの `candidates` に「成人」「18禁」などの名称候補があるか確認する。
   `genres` には取得した全ジャンルを、`incomplete` には走査が途中かを記録する。
5. **候補は自動登録しない**。楽天公式ジャンル検索APIでIDと名称を再確認し、
   そのカテゴリに全年齢向け作品が含まれないことを検証する。
6. 成人専用と裏付けられたIDだけを `verifiedAdultOnly` に追加し、
   `flutter test`、CIを実施してからPRをマージ、デプロイする。

GitHub Secretsの `RAKUTEN_APP_ID` と `RAKUTEN_ACCESS_KEY` をActions内で使用する。
値はログやArtifactsに出力しない。
監査スクリプトは `scripts/audit-rakuten-books-genres.mjs`。
ローカルからも、同じ環境変数を設定して `node scripts/audit-rakuten-books-genres.mjs` を実行できる。

### 重要：楽天サイトのアダルト区分とジャンルIDは同義ではない

楽天の公開書籍API・ジャンルAPIには、サイトのセーフサーチで成人向けに
分類されたことを保証する専用フラグを確認できていない。
楽天サイト上の「アダルト（18歳以上）」が必ずしもBooksジャンル階層の
一項目として表現されるわけではないため、**ジャンルのみで100%除外できない**。

既存のタイトル・説明文等の成人向けキーワード判定は残す。
登録済みジャンルIDは `ContentSafetyService.isAdultBook` と `filterBooks`
から未成年向け書籍一覧の除外に使われる。

## 未対応・運用上の注意

- ジャンルIDはカタログAPIから取得した `Book` オブジェクト上で利用できるが、Supabaseに書籍ジャンル情報を永続化してはいない。
- 既存投稿・プロフィール・おすすめ・外部からの直リンクのすべてに対し、サーバー側で一貫して閲覧禁止を保証する変更ではない。
- 未成年向けの完全なフィルタには、閲覧可否をサーバーで判定する仕組みと既存投稿への適用が追加で必要。
- ジャンル情報がない書籍はジャンルだけで安全と認定せず、従来の成人向けキーワード判定が継続する。
