# 個人情報変更用パスワードの復旧

## 対象

プライバシー設定を開くための **別パスワード** です。Supabase Authのログイン用パスワードではありません。
既存のハッシュから平文の元パスワードを取り出したり、パスワードをメールで送付したりしません。

## フロー

1. ログイン済みユーザーが「プライバシー設定」→「パスワードを忘れた方」を押す。
2. `begin_privacy_password_recovery` が、ログイン済みのUID、Authのメインproviderと開始時刻を保存。
3. providerが `email` の場合は、**登録済み**かつ確認済みのメールアドレスへ、Supabase Auth `signInWithOtp`（`shouldCreateUser:false`）でワンタイムリンクを送る。Google/X/Apple/Facebook/Discordの場合は同じOAuthサービスで再ログイン。
4. メールのリンク/外部認証の戻り先は `/?privacy_password_recovery=1`。アプリが設定内の再設定フォームを開く。
5. 新しいパスワードをユーザーが設定する。SQL RPC `reset_privacy_password_after_reauthentication` が、**同一UID**・**同一provider**・15分以内の要求・要求時刻以降の新しい `amr` (email → `otp`/`magiclink`, OAuth → `oauth`) を確認した場合だけ、プライバシーパスワードを新しくハッシュ化して更新する。

URLに`privacy_password_recovery=1`と入力するだけではRPCの本人確認を通れません。

## Supabase Auth 側で確認する設定

- 本番 `https://www.sharemarium.com/?privacy_password_recovery=1` と、同じパス・クエリのステージングURLを **Auth → URL Configuration → Redirect URLs** の許可対象に追加する（または明確に一致する許可パターンを設定）。OAuth側の許可リダイレクトURLも確認する。
- メールプロバイダを有効化し、利用者のメールを確認済みにする。Magic Linkテンプレートとメール送信ドメインの設定が必要。
- Magic Linkを使う場合、メールクライアントの事前アクセスによる使い捨てリンク消費に注意。必要ならSupabaseのメールOTPテンプレートと入力画面への切り替えを検討する。
- 実際のGoogle/X/メールアカウントで、リダイレクト後のJWT `amr` がサーバー条件に合うことをステージングで確認する。サービスキー、JWT、本文のパスワードをログに出さない。

## リリース順序（必須）

1. 新migration `20261030130000_allow_email_privacy_password_recovery.sql` のCI検証。
2. **本番DBにmigrationを適用**する。GitHub Actions `Deploy Database to Supabase` を手動起動し、`apply_migrations=true`, `deploy_edge_functions=false` を設定する。既に本番に未適用の別migrationがある場合、合わせて適用されうるため、必ずドライラン計画を先に確認する。
3. 新しいFlutter UIを `main` にマージ・CloudflareとVercelに配信する。
4. メール、Google、Xの実アカウントでテスト。15分超過、古いログイン、別ユーザー、失効リンク、同一アカウントの二重操作の失敗を確認する。

**SQLを先に適用しない場合、旧RPCはemailプロバイダを拒否する。**

## 注意点

- OAuthリダイレクト後の`app_metadata.provider`がメール以外の場合は、メールリンクへフォールバックしない。本人が元のログイン方法で認証し直すこと。
- 本人確認をしない自動パスワード発行・メール配送はしない。
