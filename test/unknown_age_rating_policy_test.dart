import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/services/content_safety_service.dart';

const _general = Book(
  id: '9780000000001',
  isbn: '9780000000001',
  title: '一般向けの本',
  author: '作家',
  publisher: '出版社',
  pubDate: '2026',
  coverUrl: '',
  ageRatingSource: 'unknown',
);

void main() {
  test('unknown age classification is shown to under-18 viewers', () {
    expect(_general.ageRatingSource, 'unknown');
    expect(ContentSafetyService.isAdultBook(_general), isFalse);
    expect(
      ContentSafetyService.filterBooks(
        [_general], allowAdultContent: false,
      ),
      [_general],
    );
  });

  test('confirmed restricted titles are not shown to under-18 viewers', () {
    final flagged = _general.copyWith(
      id: '9780000000002',
      adultContentFlag: true,
      ageRatingSource: 'openbd',
    );
    final adultKeyword = _general.copyWith(
      id: '9780000000003',
      title: '18禁の本',
    );
    expect(
      ContentSafetyService.filterBooks(
        [_general, flagged, adultKeyword],
        allowAdultContent: false,
      ),
      [_general],
    );
    expect(
      ContentSafetyService.filterBooks(
        [_general, flagged, adultKeyword],
        allowAdultContent: true,
      ).length,
      3,
    );
  });
}
