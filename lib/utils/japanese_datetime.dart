String formatJapaneseMonthDayTime(DateTime value) {
  final local = value.toLocal();
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}月${local.day}日${local.hour}時$minute分';
}
