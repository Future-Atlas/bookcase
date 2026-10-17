# Cloudflare Workers migration

SharemariumのFlutter Web、SEO HTML、サイトマップ、楽天APIプロキシ、広告権限判定を、1つのCloudflare WorkerとStatic Assetsで配信するための移行手順です。

## 安全方針

- VercelはCloudflare版の検証が終わるまで停止・削除しない。
- 最初は`workers.dev` URLへデプロイし、公式ドメインのDNSは変更しない。
- stagingとproductionは別Worker、別GitHub Environmentで管理する。
- production Workerが正常であることを確認してから、`www.sharemarium.com`をCustom Domainとして接続する。
- DNS切替後も、Vercelはロールバック用に短期間残す。

## Cloudflareで用意するもの

1. Cloudflareアカウントを作成する。
2. `sharemarium.com`をCloudflareへ追加する。
3. Cloudflareが案内するネームサーバーをドメイン管理会社側へ登録する。
4. Cloudflare Dashboardの **Workers & Pages** を開く。
5. **My Profile > API Tokens > Create Token** から、Workersを編集できるAPI Tokenを作成する。
6. Cloudflare Dashboard右側に表示されるAccount IDを確認する。

GitHubの`staging`と`production` Environmentへ次を登録します。

| Secret | 内容 |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | Cloudflare Workersデプロイ用API Token |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Account ID |
| `SUPABASE_URL` | 対象環境のSupabase URL |
| `SUPABASE_ANON_KEY` | 対象環境のSupabase公開anon key |
| `SUPABASE_REDIRECT_URL` | ログイン後に戻す対象環境URL |
| `RAKUTEN_APP_ID` | 楽天アプリID |
| `RAKUTEN_ACCESS_KEY` | 楽天アクセスキー |
| `RAKUTEN_AFFILIATE_ID` | 楽天アフィリエイトID |

機密値を`wrangler.jsonc`へ直接書かないでください。GitHub Actionsは、上記の値を暗号化されたWorker Secretsとして登録します。

## 検証環境

1. GitHub Actionsで **Deploy Flutter Web to Cloudflare Workers (Staging)** を手動実行する。
2. 実行結果に表示された`sharemarium-staging.<subdomain>.workers.dev`を開く。
3. ホーム、ログイン以外の公開画面、書籍検索、書籍詳細、タイムライン、楽天リンクを確認する。
4. `/sitemap.xml`がXMLを返すことを確認する。
5. Googlebot User-Agentで`/posts`と`/privacy`がHTMLを返すことを確認する。
6. workers.dev版には`X-Robots-Tag: noindex, nofollow`が付くことを確認する。
7. ログイン検証を行う場合は、検証Workerへ`staging.sharemarium.com`等のCustom Domainを接続し、Supabase AuthenticationのRedirect URLとGoogle OAuthの許可URIも同じURLへ更新する。

## 本番Workerの事前作成

1. GitHub Actionsで **Deploy Flutter Web to Cloudflare Workers (Production)** を選ぶ。
2. `confirmation`へ`DEPLOY`と入力して実行する。
3. これによりproduction Workerは作成されるが、公式ドメインのDNSはまだ変わらない。
4. ActionsのSmoke testが成功することを確認する。
5. Worker URLで公開画面とAPIを確認する。Worker URL自体は`noindex`です。

## 公式ドメインの切替

1. Cloudflare Dashboardでproduction Workerを開く。
2. **Settings > Domains & Routes > Add > Custom Domain** を開く。
3. `www.sharemarium.com`を登録する。
4. 必要に応じて`sharemarium.com`も登録し、アプリ側のcanonicalは引き続き`https://www.sharemarium.com`とする。
5. `https://www.sharemarium.com/`、`/book/...`、`/posts`、`/sitemap.xml`、`/api/rakuten`を確認する。
6. Googleログインとメールログインを確認する。
7. Search ConsoleのURL検査とサイトマップを確認する。
8. 問題がなければVercelの自動デプロイを無効化し、GitHub ActionsのVercel用ワークフローも停止する。

## ロールバック

切替直後に重大な問題が起きた場合は、CloudflareのCustom Domainを外し、直前まで使用していたVercel向けDNSへ戻します。VercelプロジェクトはCloudflareで数日間安定稼働するまで削除しません。

## 実装上の対応関係

- `build/web`: Flutter Web Static Assets
- `cloudflare/worker.mjs`: Vercel Functions互換アダプターとルーティング
- `api/*.js`: SEO・サイトマップ・楽天・広告判定の既存ロジック
- `wrangler.jsonc`: staging／production Worker設定
- `scripts/generate-legal-seo-sources.mjs`: Flutterの法務文書をWorkers向けモジュールへ同期
- `.github/workflows/deploy-cloudflare-*.yaml`: 手動デプロイ

Cloudflareの切替完了までは`vercel.json`と既存Vercelワークフローを削除しません。
