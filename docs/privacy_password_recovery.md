# プライバシー設定用パスワードの再設定（Google / X）

## 対象

Sharemariumのログイン方法は現在 **Google / Xのみ**。メールアドレスによるパスワードログインや、メールリンクによる復旧は提供しない。

このパスワードはログイン用ではなく、**プライバシー設定を開くための別パスワード**。以前の値を表示・メール送信・自動発行することはない。

## 画面フロー

1. ログイン済みの利用者が「プライバシー設定」→「パスワードを忘れた方」を押す。
2. サーバーの `begin_privacy_password_recovery` が、現在のUID・GoogleまたはXのprovider・要求時刻を記録。
3. **ログイン時と同じGoogle / X** で本人確認する。
4. OAuth終了後、`/?privacy_password_recovery=1` に戻り、**初回の個人情報変更用パスワード設定画面と同じレイアウト**で「**新しいパスワードを設定**」ページを開く。
5. 新しいパスワードと確認用パスワードを入力 →「再設定する」。
6. サーバーで同一ユーザー・同一provider・15分以内の要求・要求開始以降の `amr.method=oauth` を検証し、合格の場合にのみ新パスワードのハッシュを保存。元のプライバシー設定に戻る。

**URLを手動で開いても本人確認は省略できず、SQL側で未認証の更新を拒否する。**

## Supabase Authの設定

- 本番用 `https://www.sharemarium.com/?privacy_password_recovery=1` とステージングの同等URLを、Auth → URL Configuration → Redirect URLsに許可する（または明確に一致する許可パターン）。
- Google/XのOAuth接続設定を確認。実際のログインでリダイレクト・JWT `amr`・同一ユーザー条件をステージングでテストする。
- OAuthトークン・機密情報・パスワードをログに記録しない。

## マイグレーションと本番公開の順番

- `20261030130000_allow_email_privacy_password_recovery.sql` は過去にステージングへ適用済みのため**編集しない**。本番では新しいマイグレーションを含めて実行すると順に適用される。
- `20261030130100_restrict_privacy_password_recovery_to_oauth.sql` が最終仕様（Google / X限定）。**後のマイグレーションがメールによる復旧を無効化する**。
- 本番DBへ実適用を確認してから、Flutter UIを本番 `main` に反映する。通常のpushではドライランだけであり、`Deploy Database to Supabase` を `main`・`apply_migrations=true`・`deploy_edge_functions=false` で手動起動する。
- Webの動作確認はGoogle・X両方、既存のログインセッションのみ、異なるOAuthアカウント、15分経過、再設定後のログイン・プライバシー設定で実施する。
