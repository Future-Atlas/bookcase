# サブスクリプション販売開始のサーバー側ゲート

2026-10-12: 現在のSharemariumは無料運用で、Asana上のPlus/Premiumは予定仕様です。Flutterの`FeatureFlags.subscriptionUiEnabled = false`だけでは、認証済みユーザーがEdge Functionを直接呼ぶことまで止められません。

## 初期状態

- **販売は無効**: Supabase Edge Functions runtime の`BILLING_SALES_ENABLED`が正確に文字列`true`の時にのみ、`billing-checkout`と`billing-change-plan`を処理します。変数未設定・`false`・`1`等はHTTP 503で拒否します。
- `billing-cancel-subscription` と `billing-webhook` は止めません。すでに存在する契約の解約・返金・認証済みStripeイベントの整合性維持のため必要です。Webhook署名検証やDBのRLS/RPCは既存のまま。
- 同意文書、料金、決済契約、実際の決済機能はこの変更で公開しません。Stripe Secretの有無を販売開始判定に使いません。
- 開発・ステージング・本番の環境ごとに独立したSupabase Edge Function Secretを設定します。**GitHub ActionsのEnvironment secretsを設定してもEdge Function runtimeの変数には自動反映されません。**
- 新規登録・既存契約更新・管理者特例のモデルは既存の契約DB/RPCと切り離して考えます。販売フラグは`checkout/upgrade`だけに適用し、過去の契約の失効処理や解約を妨げません。

## 将来、販売開始を承認する前のゲート

1. 決済事業者/Stripe本番契約、価格ID、無料体験の扱い、解約・返金・支払猶予の仕様がAsanaと一致しているか確認。
2. 利用規約、プライバシーポリシー、外部送信、特商法表示、最終確認画面及び解約導線を専門家確認。適切な利用者同意・通知を実施。
3. テストモードでCheckout→Webhook重複送信→プラン変更→解約→失効→再開をE2E検証。重複請求やフラグ切替前後の有料アクセスを確認。
4. ステージングのEdge Function runtimeで、`BILLING_SALES_ENABLED`が未設定のとき、ログイン済みでもCheckout/Plan ChangeがHTTP 503となり、Stripeへ通信しないことを確認。
5. テスト環境でのみ、許可された管理者が`BILLING_SALES_ENABLED=true`を設定し、連携のE2Eテストを実施。その後フラグを無効へ戻す。
6. 本番は別途、二重承認・実署名/本番決済アカウント・プラン/料金の最終確認後にSupabase Dashboardからruntime変数を設定。Flutter UIフラグも別途変更し、リリース/復旧経路を確認。

**注意**: 本PRでは環境変数を設定しません。本番売上や課金を開始する機能ではなく、誤販売を防ぐための初期閉鎖ゲートです。
