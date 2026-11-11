import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Paste into the selected range, or append when no selection is available.
/// The source remains the platform clipboard, so the user explicitly controls
/// what is pasted. No clipboard text is logged or sent to analytics.
Future<bool> pasteClipboardInto(TextEditingController controller) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text;
  if (text == null || text.isEmpty) return false;

  final current = controller.value;
  final selection = current.selection;
  final validSelection = selection.isValid &&
      selection.start >= 0 &&
      selection.end <= current.text.length;
  final start = validSelection ? selection.start : current.text.length;
  final end = validSelection ? selection.end : current.text.length;
  final updated = current.text.replaceRange(start, end, text);
  controller.value = TextEditingValue(
    text: updated,
    selection: TextSelection.collapsed(offset: start + text.length),
  );
  return true;
}

/// Copy only on an explicit user action. Password copies can remain in the
/// system clipboard after the page closes; the UI should warn about this.
Future<void> copyFieldText(TextEditingController controller) async {
  await Clipboard.setData(ClipboardData(text: controller.text));
}
