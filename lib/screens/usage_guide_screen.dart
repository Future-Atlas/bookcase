import 'package:flutter/material.dart';

/// In-app guide for current Sharemarium features. Keep limitations in sync
/// with the actual product rather than promising planned functionality.
class UsageGuideScreen extends StatelessWidget {
  const UsageGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const entries = <_GuideSection>[
      _GuideSection(
        '読了（投稿機能）',
        Icons.rate_review_outlined,
        '本を読んだらマイページの「投稿」から右下の＋を押し、作品名・著者名などで本を探します。作品を選び、評価と感想を入力して投稿してください。書籍毎にある書籍の詳細ページにある「読了」ボタンからも投稿することができます。ネタバレを含む場合は「ネタバレあり投稿」を選択することで、まだその本を読んでいない人に感想を隠すことができます。',
        '感想は1〜1,000文字（空白だけでは投稿できません）。投稿にはログインが必要です。同じ書籍への重複投稿はできません。年齢制限のある書籍や投稿には閲覧・投稿の制限があります。非公開アカウントの場合、あなたの投稿はあなたのフォロワーにしか表示されません。',
      ),
      _GuideSection(
        'My 本棚',
        Icons.menu_book_outlined,
        'マイページの「My 本棚」には、読了して投稿した書籍が並びます。本の表紙を選ぶと書籍情報や関連するレビューを確認できます。投稿した書籍を整理・振り返るための、あなたの本棚です。',
        '投稿を削除すると、その本はMy 本棚からも削除されます。非公開アカウントの場合、本棚は閲覧権限がないと表示されません。',
      ),
      _GuideSection(
        '読書カレンダー',
        Icons.calendar_month_outlined,
        'マイページの「カレンダー」を開き、右下の＋から本を選ぶと読書タイマーを始められます。読書を終えたら「計測を終了して記録」を押すと、その日の読書時間がカレンダーに反映されます。日付を選んで記録を振り返ることができます。',
        '読書時間は実際の開始・終了時刻から記録されます。過去の記録の手動追加・編集はできず、1回の計測は最大24時間です。画面を閉じても計測中の記録は残り、再ログイン時やカレンダーから確認・再開できます。公開対象はフォロワーですが、設定の「読書カレンダーを表示しない人」で個別に非公開にできます。非公開にした相手にはカレンダーの更新通知も送られません。',
      ),
      _GuideSection(
        '読みたい！',
        Icons.bookmark_add_outlined,
        '書籍ページ、書籍検索結果、または投稿の「読みたい！」を押すと、マイページの「読みたい！」にその本が追加されます。もう一度押すと解除できます。次に読む本の候補を整理するときに使ってください。',
        'ログインした利用者が無料で利用できます。同じ書籍は1ユーザーにつき1冊までです。読了済みの書籍は追加できません。書籍ページの人数は、同じ本を読みたいと思っているユーザーを重複なく数えます。書籍ページと投稿のボタンは同じ登録状態を共有します。',
      ),
      _GuideSection(
        'タイムライン',
        Icons.dynamic_feed_outlined,
        '画面下部またはメニューの「タイムライン」から他のユーザーの読書レビューを閲覧できます。各投稿でリアクションを付けたり、気になった本を「読みたい！」に保存したりできます。投稿者のプロフィールからフォローすることもできます。',
        'リアクションなどの操作にはログインが必要です。自分の投稿に自分でリアクションすることはできません。非公開アカウントやブロック関係、年齢制限によって閲覧できない投稿があります。一般ユーザーによる返信機能は現在利用できません。',
      ),
      _GuideSection(
        'カーラー設定',
        Icons.palette_outlined,
        '左上のハンバーガーメニューから「設定」を開きます。「ダークモード」のスイッチで明るい表示と暗い表示を切り替えられます。自分のページの色を変更するときは「アカウント設定」→「ページカラー」で好きな利用可能色を選択し、「保存する」を押してください。',
        'ページカラーには最初から使える標準色と、投稿実績によって解禁される色があります。解禁の節目は投稿10・25・50・100件、その後50件ごとです。解禁した色は恒久的に使えますが、特典で解禁した色の取り消し・変更はできません。ダークモードは自分の表示設定、ページカラーは他のユーザーにも見える外枠などの色です。',
      ),
    ];

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: ListView(
          key: const ValueKey('usage-guide-sections'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text('Sharemariumの使い方',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '6つの機能について、操作方法と利用上の制限を説明します。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < entries.length; i++) ...[
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  key: ValueKey('usage-guide-section-$i'),
                  initiallyExpanded: i == 0,
                  leading: Icon(entries[i].icon,
                    color: theme.colorScheme.primary),
                  title: Text(entries[i].heading,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '使い方',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entries[i].instructions,
                      style: const TextStyle(fontSize: 16, height: 1.75),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '制限・注意点',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Keep every existing note, but put each sentence on its
                    // own line with ※ so restrictions are easy to scan.
                    for (final sentence in entries[i].limitations.split('。'))
                      if (sentence.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text(
                            '※ ${sentence.trim()}。',
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuideSection {
  const _GuideSection(this.heading, this.icon, this.instructions, this.limitations);
  final String heading;
  final IconData icon;
  final String instructions;
  final String limitations;
}
