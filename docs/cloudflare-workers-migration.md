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
2. **Workers & Pages** で `workers.dev` のアカウントサブドメインを確認する。
3. **API Tokens** でWorkersデプロイ用のAPI Tokenを作成する。
4. Account IDを確認する。
5. **この段階では `sharemarium.com` のネームサーバーや既存メールのDNSレコードを変更しない。** `workers.dev` の本番Worker公開にはDNS移行は不要。

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

1. `develop`へのpushで **Deploy Flutter Web to Cloudflare Workers (Staging)** が自動実行される（`develop`で手動再実行も可能）。
2. 実行結果に表示された`sharemarium-staging.<subdomain>.workers.dev`を開く。
3. ホーム、ログイン以外の公開画面、書籍検索、書籍詳細、タイムライン、楽天リンクを確認する。
4. `/sitemap.xml`がXMLを返すことを確認する。
5. Googlebot User-Agentで`/posts`と`/privacy`がHTMLを返すことを確認する。
6. workers.dev版には`X-Robots-Tag: noindex, nofollow`が付くことを確認する。
7. ログイン検証を行う場合は、検証Workerへ`staging.sharemarium.com`等のCustom Domainを接続し、Supabase AuthenticationのRedirect URLとGoogle OAuthの許可URIを合わせる。`workers.dev`で公開しても**既存の`staging.sharemarium.com`が自動的に切り替わることはない**。
8. GitHub ActionsでのVercelステージングは`develop`・確認欄`ROLLBACK`の**手動フォールバックのみ**とする。VercelのネイティブGit連携は別設定なので、自動Previewが不要ならVercel管理画面で整理する。

## 本番Workerの事前作成

1. GitHub Actionsで **Deploy Flutter Web to Cloudflare Workers (Production)** を選び、ブランチを必ず`main`にする。リポジトリのデフォルトブランチは`develop`なので、手動ワークフローが一覧に表示されるよう、Cloudflareワークフローファイルを`main`だけでなく`develop`にも反映する。
2. `confirmation`へ`DEPLOY`と入力して実行する。CloudflareアカウントID・デプロイトークン・Supabase・楽天の必須Secretsが未設定ならデプロイ前に失敗する。
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
8. DNS・ネームサーバーの移管が必要な場合は、切替前に現在の全DNSレコード（MX、SPF、DKIM、DMARCを含む）を確認し、Cloudflare側へ正しく移してから切り替える。メール送受信の確認も実施する。
9. Vercel本番のGitHub Actionsは自動デプロイ無効・手動ロールバック専用で保持する。ただし**Vercel本体のGit連携も別途自動Production/Previewデプロイを行う場合がある**。Cloudflareへのドメイン切替後、VercelのSettings > Gitで自動デプロイを止めるかGit連携を解除する（ステージングへの影響を先に確認）。

## ロールバック

切替直後に重大な問題が起きた場合は、CloudflareのCustom Domainを外し、直前まで使用していたVercel向けDNSへ戻します。VercelプロジェクトはCloudflareで数日間安定稼働するまで削除しません。

## 実装上の対応関係

- `build/web`: Flutter Web Static Assets
- `cloudflare/worker.mjs`: Vercel Functions互換アダプターとルーティング
- `api/*.js`: SEO・サイトマップ・楽天・広告判定の既存ロジック
- `wrangler.jsonc`: staging／production Worker設定
- `scripts/generate-legal-seo-sources.mjs`: Flutterの法務文書をWorkers向けモジュールへ同期
- `.github/workflows/deploy-cloudflare-production.yaml`: 手動本番デプロイ
- `.github/workflows/deploy-cloudflare-staging.yaml`: `develop`へのpushで自動ステージングデプロイ（手動再実行も可能）

`vercel.json`とVercelの2つのワークフローは、ステージング・本番それぞれの**手動フォールバック専用**として保持します。GitHub Actions経由のVercel自動デプロイは停止しますが、VercelのネイティブGit連携の自動デプロイは別途管理が必要です。

## Workers Freeでの静的配信最適化

`wrangler.jsonc`の`assets.run_worker_first`は、SEO/API/サイトマップ/robots等の必要なルートだけをWorker経由にします。
FlutterのJS・CSS・画像などの静的ファイルはStatic Assetsが直接返し、Workers Freeの実行リクエスト枠を消費しない構成です。
ルーティングを追加したときは、対象のSEO/APIルートが配列に含まれていることを確認します。

## 本番Workerを先に公開する手順

独自ドメインのDNSを変更せず、最初に`sharemarium-production.<account-subdomain>.workers.dev`へ手動デプロイ可能です。
GitHubの`production` Environmentへ`CLOUDFLARE_API_TOKEN`と`CLOUDFLARE_ACCOUNT_ID`を登録し、既存のSupabase・楽天用Secretsを確認してから、Actionsで本番デプロイを手動実行します。
`confirmation`に`DEPLOY`を入力してください。スモークテストの成功後、独自ドメインは別途切り替えます。

## Preview環境と旧デプロイ設定の整理

| 表示名・設定 | 管理場所 | 扱い |
| --- | --- | --- |
| GitHub Environment `production` | GitHub Settings > Environments | Cloudflare本番用Secrets・保護設定。維持 |
| GitHub Environment `staging` | GitHub Settings > Environments | CloudflareステージングとSupabaseのSecrets。Vercelフォールバック用にも維持 |
| Vercel `Preview` | Vercel Project > Settings | ステージングの手動フォールバック。Vercel Git連携が有効ならPRのPreview作成は引き続き発生し得る |
| Vercel `Production` | Vercel Project > Settings | DNS切替まで現行の本番、その後は一時復旧先 |
| GitHubの`Supabase Preview`チェック | Supabase連携の設定 | リポジトリ内のワークフローではない。不要なら連携元で無効化 |
| GitHubの別の`Preview`環境 | GitHub Settings > Environments | Vercel/GitHub Apps等が作った場合がある。参照先と必要な保護設定を確認してから手動整理 |

`seo_preview=1`はSEO向けHTMLの確認機能であり、VercelのPreview環境ではありません。SEOテストに必要なので削除しません。

### 順次廃止する条件

1. Cloudflare本番Workerを`workers.dev`で検証し、独自ドメイン・OAuth・SEO・楽天API・広告・メールを切り替えて動作確認する。
2. Vercelの不要なPRごとのPreview作成は、**Vercel管理画面のGit連携設定**で停止する。YAMLの削除だけでは停止しない。
3. Cloudflareステージングが機能しても、Vercelステージングの手動フォールバック用Workflow・Secrets・`vercel.json`は残す。フォールバック自体を廃止する判断をした場合にだけ、別PRで整理する。
4. Supabase Preview連携や未使用GitHub Environmentは、Branch Protectionの必須チェックなどの依存を確かめてから連携元・GitHub管理画面で整理する。
5. Cloudflare本番を安定運用できてから、Vercel復旧手段をいつまで維持するかを決める。

**名前が`Preview`だからという理由だけで環境を消さないこと。** 既存のステージング・PR検証の動作を守るためです。
