import 'package:flutter/material.dart';

/// Keeps publisher cover artwork complete inside a circular badge.
class ReadingCoverArt extends StatelessWidget {
  const ReadingCoverArt({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final parsed = Uri.tryParse(url.trim());
    final secure = parsed != null &&
        parsed.scheme == 'https' &&
        parsed.host.isNotEmpty &&
        parsed.userInfo.isEmpty;
    if (!secure) {
      return const Center(child: Icon(Icons.menu_book_outlined, size: 32));
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      // Show image via an HTML element on Flutter Web when the source does not
      // send CORS headers, matching the search card's rendering approach.
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      errorBuilder: (context, error, stackTrace) =>
          const Center(child: Icon(Icons.menu_book_outlined, size: 32)),
    );
  }
}
