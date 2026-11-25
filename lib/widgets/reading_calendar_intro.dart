import 'package:flutter/material.dart';

/// Release announcement. The diagrams illustrate the flow using example
/// data, so opening this dialog never reads or starts a reading session.
class ReadingCalendarIntro extends StatelessWidget {
  const ReadingCalendarIntro({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '読書カレンダー　導入！',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '閉じる',
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('読んだ時間を、本ごとに記録できるようになりました。'),
                    const _Step(
                      number: 1,
                      title: '読む本を選ぶ',
                      body: 'マイページの「カレンダー」で右下の「＋」を押し、本を検索して選びます。',
                      icon: Icons.menu_book_rounded,
                      example: '＋　本を選ぶ',
                    ),
                    const _Step(
                      number: 2,
                      title: '読書を計測する',
                      body: '「読書を開始する」を押します。途中で画面を閉じても、カレンダーから計測中の本に戻れます。',
                      icon: Icons.timer_outlined,
                      example: '00:25:00',
                    ),
                    const _Step(
                      number: 3,
                      title: '終了してカレンダーに記録',
                      body:
                          '「計測を終了して記録」を押すと、本と読書時間が保存されます。日付を選ぶと、その日に読んだ本と時間を確認できます。',
                      icon: Icons.calendar_month_outlined,
                      example: '記録例　25分',
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '計測中は自分だけに表示されます。終了後は、カレンダーを閲覧できるフォロワーに共有・通知されます。',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xffb71c1c),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('読書カレンダーを見に行く'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.icon,
    required this.example,
  });
  final int number;
  final String title, body, example;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 82,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  // Miniatures of the book picker, timer and saved calendar entry.
                  // Kept local so the guide also works with external images blocked.
                  SizedBox(
                    width: 70,
                    height: 55,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (number == 1) ...[
                            const Positioned(
                              top: 4,
                              left: 4,
                              child: Icon(Icons.search, size: 12),
                            ),
                            Positioned(
                              top: 9,
                              left: 18,
                              right: 6,
                              child: Container(
                                height: 2,
                                color: colors.outlineVariant,
                              ),
                            ),
                            Positioned(
                              bottom: 5,
                              left: 9,
                              child: Icon(icon, size: 28),
                            ),
                            Positioned(
                              bottom: 5,
                              right: 4,
                              child: Icon(
                                Icons.add_circle,
                                size: 15,
                                color: colors.primary,
                              ),
                            ),
                          ] else if (number == 2) ...[
                            Positioned(top: 3, child: Icon(icon, size: 33)),
                            Positioned(
                              bottom: 4,
                              child: Icon(
                                Icons.stop_circle,
                                size: 14,
                                color: colors.error,
                              ),
                            ),
                          ] else ...[
                            Positioned(top: 4, child: Icon(icon, size: 34)),
                            Positioned(
                              bottom: 5,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.menu_book,
                                    size: 10,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 3),
                                  Container(
                                    width: 22,
                                    height: 3,
                                    color: colors.outline,
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(
                                    Icons.check,
                                    size: 10,
                                    color: colors.primary,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    example,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$number. $title',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
