import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/services/content_safety_service.dart';
import 'package:sharemarium/config/restricted_rakuten_genres.dart';

Book sampleBook({List<String> genreIds = const []}) => Book(
  id: '9780000000001',
  title: '一般的な書名',
  author: '著者名',
  publisher: '出版社',
  pubDate: '',
  isbn: '9780000000001',
  coverUrl: '',
  rakutenGenreIds: genreIds,
);

void main() {
  test('登録ジャンルは正しいID・成人専用の根拠があるものだけを許可', () {
    for (final entry in RestrictedRakutenGenres.verifiedAdultOnly.entries) {
      expect(entry.key, matches(RegExp(r'^\\d{3}(?:\\d{3})*\  test('楽天ジャンルIDを先頭ゼロを残して分割し、重複や不正値を除く', () {
    expect(
      Book.parseRakutenGenreIds('001004008 / 001021002 / 001004008 / invalid'),
      ['001004008', '001021002'],
    );
    expect(Book.parseRakutenGenreIds(null), isEmpty);
    expect(Book.parseRakutenGenreIds(''), isEmpty);
    expect(Book.parseRakutenGenreIds(['001004008', '005001']), [
      '001004008', '005001',
    ]);
    expect(Book.parseRakutenGenreIds('1012/001004008x'), isEmpty);
  });

  test('楽天レスポンスのbooksGenreIdをBookモデルで利用できる', () {
    final book = Book.fromRakutenJson(const <String, dynamic>{
      'title': '書籍名',
      'author': '著者名',
      'publisherName': '出版社',
      'isbn': '9780000000001',
      'booksGenreId': '001004008/001021002',
    });
    expect(book.rakutenGenreIds, ['001004008', '001021002']);
    expect(book.copyWith(title: '変更後').rakutenGenreIds, book.rakutenGenreIds);
    expect(book.belongsToRakutenGenre('001004'), isTrue);
    expect(book.belongsToRakutenGenre('001021'), isTrue);
    expect(book.belongsToRakutenGenre('001002'), isFalse);
    expect(book.belongsToRakutenGenre('0010040'), isFalse);
  });

  test('認証済み成人向けジャンルのみを子ジャンルまで除外できる', () {
    final general = sampleBook(genreIds: const ['001004008']);
    final restricted = sampleBook(genreIds: const ['001004008', '001999002']);
    // Deliberately synthetic: real genres must be reviewed before blocking.
    const vettedRestrictedIds = <String>{'001999'};
    expect(
      ContentSafetyService.hasRestrictedRakutenGenre(
        restricted, restrictedGenreIds: vettedRestrictedIds,
      ),
      isTrue,
    );
    expect(
      ContentSafetyService.filterBooks(
        [general, restricted],
        allowAdultContent: false,
        restrictedGenreIds: vettedRestrictedIds,
      ),
      [general],
    );
    expect(
      ContentSafetyService.filterBooks(
        [general, restricted],
        allowAdultContent: true,
        restrictedGenreIds: vettedRestrictedIds,
      ),
      [general, restricted],
    );
  });

  test('ジャンルID未取得の場合は既存の成人向けキーワード判定を維持する', () {
    final normal = sampleBook();
    final flagged = normal.copyWith(title: '成人向け作品');
    expect(ContentSafetyService.isAdultBook(normal), isFalse);
    expect(ContentSafetyService.isAdultBook(flagged), isTrue);
    expect(ContentSafetyService.filterBooks(
      [normal, flagged],
      allowAdultContent: false,
    ), [normal]);
  });
}
)));
      expect(
        RestrictedRakutenGenres.neverBlockBroadGenres.contains(entry.key),
        isFalse,
        reason: '一般向け書籍を含む親ジャンルはブロック不可: ${entry.key}',
      );
      expect(entry.value, contains('https://'), reason: '登録には公式な根拠URLが必要');
      expect(entry.value, matches(RegExp(r'\\d{4}-\\d{2}-\\d{2}')));
    }
    expect(
      ContentSafetyService.restrictedRakutenGenreIds,
      RestrictedRakutenGenres.verifiedAdultOnly.keys.toSet(),
    );
  });

  test('楽天ジャンルIDを先頭ゼロを残して分割し、重複や不正値を除く', () {
    expect(
      Book.parseRakutenGenreIds('001004008 / 001021002 / 001004008 / invalid'),
      ['001004008', '001021002'],
    );
    expect(Book.parseRakutenGenreIds(null), isEmpty);
    expect(Book.parseRakutenGenreIds(''), isEmpty);
    expect(Book.parseRakutenGenreIds(['001004008', '005001']), [
      '001004008', '005001',
    ]);
    expect(Book.parseRakutenGenreIds('1012/001004008x'), isEmpty);
  });

  test('楽天レスポンスのbooksGenreIdをBookモデルで利用できる', () {
    final book = Book.fromRakutenJson(const <String, dynamic>{
      'title': '書籍名',
      'author': '著者名',
      'publisherName': '出版社',
      'isbn': '9780000000001',
      'booksGenreId': '001004008/001021002',
    });
    expect(book.rakutenGenreIds, ['001004008', '001021002']);
    expect(book.copyWith(title: '変更後').rakutenGenreIds, book.rakutenGenreIds);
    expect(book.belongsToRakutenGenre('001004'), isTrue);
    expect(book.belongsToRakutenGenre('001021'), isTrue);
    expect(book.belongsToRakutenGenre('001002'), isFalse);
    expect(book.belongsToRakutenGenre('0010040'), isFalse);
  });

  test('認証済み成人向けジャンルのみを子ジャンルまで除外できる', () {
    final general = sampleBook(genreIds: const ['001004008']);
    final restricted = sampleBook(genreIds: const ['001004008', '001999002']);
    // Deliberately synthetic: real genres must be reviewed before blocking.
    const vettedRestrictedIds = <String>{'001999'};
    expect(
      ContentSafetyService.hasRestrictedRakutenGenre(
        restricted, restrictedGenreIds: vettedRestrictedIds,
      ),
      isTrue,
    );
    expect(
      ContentSafetyService.filterBooks(
        [general, restricted],
        allowAdultContent: false,
        restrictedGenreIds: vettedRestrictedIds,
      ),
      [general],
    );
    expect(
      ContentSafetyService.filterBooks(
        [general, restricted],
        allowAdultContent: true,
        restrictedGenreIds: vettedRestrictedIds,
      ),
      [general, restricted],
    );
  });

  test('ジャンルID未取得の場合は既存の成人向けキーワード判定を維持する', () {
    final normal = sampleBook();
    final flagged = normal.copyWith(title: '成人向け作品');
    expect(ContentSafetyService.isAdultBook(normal), isFalse);
    expect(ContentSafetyService.isAdultBook(flagged), isTrue);
    expect(ContentSafetyService.filterBooks(
      [normal, flagged],
      allowAdultContent: false,
    ), [normal]);
  });
}
