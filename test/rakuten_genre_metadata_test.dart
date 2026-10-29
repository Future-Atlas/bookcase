import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/services/content_safety_service.dart';

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
    final restricted = sampleBook(genreIds: const ['001004008', '001021002']);
    const vettedRestrictedIds = <String>{'001021'};
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
