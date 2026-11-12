import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/api/ndl_api.dart';
const xml=r'''<?xml version="1.0"?>
<rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:openSearch="http://a9.com/-/spec/opensearch/1.1/">
<channel><openSearch:totalResults>62</openSearch:totalResults>
<item><title>英語の小説</title><dc:creator>Writer</dc:creator><dc:publisher>Publisher</dc:publisher><dc:identifier xsi:type="dcndl:ISBN">9784101010014</dc:identifier><dcterms:issued>2026-10</dcterms:issued><dc:subject xsi:type="dcndl:NDC10">933</dc:subject><dc:language>eng</dc:language></item>
<item><title>ISBNなし</title><dc:identifier>http://id.ndl.go.jp/bib/123</dc:identifier></item>
<item><title>重複</title><dc:identifier xsi:type="dcndl:ISBN">9784101010014</dc:identifier></item>
</channel></rss>''';
void main(){
 test('RSS raw slots and dedup are independent',(){
   final result=NdlApi.parseSearchPage(xml,start:1,count:3);
   expect(result.rawCount,3);expect(result.hasMore,isTrue);expect(result.books.length,1);
   final book=result.books.single;
   expect(book.isbn,'9784101010014');expect(book.author,'Writer');
   expect(book.languageCode,'eng');expect(book.ndcCode,'933');
   expect(book.pubDate,'2026-10');
 });
 test('one-based offset and books filter',(){
   final u=NdlApi.searchUri(title:'夏目',start:21,count:10);
   expect(u.path,'/api/ndl');expect(u.queryParameters['idx'],'21');
   expect(u.queryParameters['mediatype'],'books');
   expect(u.queryParameters['title'],'夏目');
 });
 test('ISBN-less rows do not end pagination early',(){
   final result=NdlApi.parseSearchPage(xml,start:20,count:3);
   expect(result.books.length,1);expect(result.rawCount,3);expect(result.hasMore,isTrue);
 });
 test('mixed-language metadata is retained but not treated as eng-only',(){
   const mixed=r'''<rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><channel><item><title>Bilingual Literature</title><dc:identifier xsi:type="dcndl:ISBN">9784101010014</dc:identifier><dc:language>jpn</dc:language><dc:language>eng</dc:language></item></channel></rss>''';
   final books=NdlApi.parseBooks(mixed);
   expect(books.length,1);
   expect(books.single.languageCode,'jpn eng');
   expect(NdlApi.isEnglishLanguage(books.single),false);
 });

 test('hyphenated ISBN in official NDL identifiers is normalized',(){
   const xml=r'''<?xml version="1.0"?>
   <rss xmlns:dc="http://purl.org/dc/elements/1.1/"
        xmlns:dcterms="http://purl.org/dc/terms/"
        xmlns:dcndl="http://ndl.go.jp/dcndl/terms/"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <channel>
      <item><title>ハイフン付きISBN</title>
        <dc:identifier xsi:type="dcndl:ISBN">978-4-297-13633-8</dc:identifier>
      </item>
      <item><title>出版者からのISBN</title>
        <dcterms:identifier rdf:datatype="http://ndl.go.jp/dcndl/terms/ISBN">978-4-06-541524-5</dcterms:identifier>
      </item>
      <item><title>書誌番号のみ</title>
        <dc:identifier>https://id.ndl.go.jp/bib/123456789</dc:identifier>
      </item>
    </channel>
   </rss>''';
   final batch=NdlApi.parseSearchPage(xml,start:1,count:3,genre:'新着');
   expect(batch.rawCount,3);
   expect(batch.books.length,2);
   expect(batch.books.map((b)=>b.isbn),
     ['9784297136338','9784065415245']);
   expect(batch.books.every((b)=>b.genre=='新着'),true);
 });

 test('ISBN prefixes are accepted without accepting arbitrary numeric IDs',(){
   const xml=r'''<rss xmlns:dc="http://purl.org/dc/elements/1.1/"><channel>
     <item><title>Real</title><dc:identifier>ISBN: 978-4-297-13633-8</dc:identifier></item>
     <item><title>Not a book</title><dc:identifier>NDL ID: 1234567890</dc:identifier></item>
     <item><title>Only a link</title><dc:identifier>https://example.jp/bib/9784297136338</dc:identifier></item>
   </channel></rss>''';
   final result=NdlApi.parseBooks(xml);
   expect(result.length,1);
   expect(result.single.isbn,'9784297136338');
 });

 test('HTML or XML errors are never accepted as legitimate empty search results',(){
   expect(
     () => NdlApi.parseSearchPage('<html><body>blocked</body></html>'),
     throwsFormatException,
   );
   expect(
     () => NdlApi.parseSearchPage('<error>temporarily unavailable</error>'),
     throwsFormatException,
   );
   final empty = NdlApi.parseSearchPage('<rss><channel></channel></rss>');
   expect(empty.books, isEmpty);
   expect(empty.rawCount, 0);
 });

}
