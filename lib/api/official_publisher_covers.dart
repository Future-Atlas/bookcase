/// Minimal, ISBN-exact publisher-hosted cover fallbacks for a book-introduction
/// service. This is NOT a general image search, crawler or bulk downloader.
///
/// Each publisher explicitly permits using its own cover images to introduce
/// books on websites, including individual/commercial introductions.
/// Akane: https://www.akaneshobo.co.jp/mail/form_copyright/coveronly.php
/// Goken: https://www.goken-net.co.jp/info/company_profile.html
///
/// Only publisher-assigned, valid ISBN-13 numbers may produce a fixed URL. If a
/// publisher removes the image or the URL layout changes, the image widget's
/// errorBuilder shows its title placeholder. No guessed other source follows.
class OfficialPublisherCovers {
  OfficialPublisherCovers._();

  static bool _isValidIsbn13(String isbn) {
    if (!RegExp(r'^97[89][0-9]{10}$').hasMatch(isbn)) return false;
    var sum = 0;
    for (var i = 0; i < 13; i++) {
      final digit = isbn.codeUnitAt(i) - 48;
      sum += digit * (i.isEven ? 1 : 3);
    }
    return sum % 10 == 0;
  }

  /// URL templates verified against multiple ISBN-exact publisher book pages.
  /// Goken exposes a low-resolution cover intended for web presentation.
  /// Akane asks users to use the cover image shown on its official site.
  /// Direct image requests need no separate API credential.
  static String? coverUrlForIsbn(String isbn) {
    if (!_isValidIsbn13(isbn)) return null;

    // あかね書房: ISBN 978-4-251-xxxxx-x
    if (isbn.startsWith('9784251')) {
      return 'https://www.akaneshobo.co.jp/data/book_imgs_250/$isbn.jpg';
    }

    // 語研: ISBN 978-4-87615-xxx-x
    if (isbn.startsWith('978487615')) {
      return 'https://www.goken-net.co.jp/image//large/$isbn.jpg';
    }
    return null;
  }
}
