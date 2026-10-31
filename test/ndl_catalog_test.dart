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
}
