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


 test('real OpenSearch-style RSS without language must not pass home filters', () {
   const raw=r'''<rss xmlns:dc="http://purl.org/dc/elements/1.1/"
     xmlns:dcndl="http://ndl.go.jp/dcndl/terms/"
     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><channel>
     <item><title>日本の本</title>
     <dc:identifier xsi:type="dcndl:ISBN">978-4-297-13633-8</dc:identifier>
     </item>
     </channel></rss>''';
   final books=NdlApi.parseBooks(raw);
   expect(books.length, 1);
   expect(books.single.languageCode, '');
   expect(NdlApi.isJapaneseLanguage(books.single), false);
   expect(NdlApi.isEnglishLanguage(books.single), false);
 });

 test('SRU DC-NDL decodes strict languages with typed ISBNs and raw offsets', () {
   const sru=r'''<srw:searchRetrieveResponse
       xmlns:srw="http://www.loc.gov/zing/srw/"
       xmlns:dcndl="http://ndl.go.jp/dcndl/terms/"
       xmlns:dcterms="http://purl.org/dc/terms/"
       xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
     <srw:numberOfRecords>5</srw:numberOfRecords><srw:records>
       <srw:record><srw:recordData><rdf:RDF><dcndl:BibResource>
         <dcterms:title>和書</dcterms:title>
         <dcterms:identifier rdf:datatype="http://ndl.go.jp/dcndl/terms/ISBN">978-4-297-13633-8</dcterms:identifier>
         <dcterms:language rdf:datatype="http://purl.org/dc/terms/ISO639-2">jpn</dcterms:language>
         <dcndl:originalLanguage>eng</dcndl:originalLanguage>
       </dcndl:BibResource></rdf:RDF></srw:recordData></srw:record>
       <srw:record><srw:recordData><rdf:RDF><dcndl:BibResource>
         <dcterms:title>English Book</dcterms:title>
         <dcterms:identifier rdf:datatype="http://ndl.go.jp/dcndl/terms/ISBN">978-4-06-541524-5</dcterms:identifier>
         <dcterms:language>eng</dcterms:language>
       </dcndl:BibResource></rdf:RDF></srw:recordData></srw:record>
       <srw:record><srw:recordData><rdf:RDF><dcndl:BibResource>
         <dcterms:title>Bilingual Book</dcterms:title>
         <dcterms:identifier rdf:datatype="http://ndl.go.jp/dcndl/terms/ISBN">978-4-10-101001-4</dcterms:identifier>
         <dcterms:language>jpn</dcterms:language>
         <dcterms:language>eng</dcterms:language>
       </dcndl:BibResource></rdf:RDF></srw:recordData></srw:record>
       <srw:record><srw:recordData><rdf:RDF><dcndl:BibResource>
         <dcterms:title>Unknown Language</dcterms:title>
         <dcterms:identifier rdf:datatype="http://ndl.go.jp/dcndl/terms/ISBN">978-4-08-752001-6</dcterms:identifier>
       </dcndl:BibResource></rdf:RDF></srw:recordData></srw:record>
     </srw:records></srw:searchRetrieveResponse>''';
   final batch=NdlApi.parseSruPage(sru,start:1,count:4,genre:'和書');
   expect(batch.rawCount,4);
   expect(batch.hasMore,true);
   expect(batch.books.length,4);
   expect(batch.books.first.isbn,'9784297136338');
   expect(NdlApi.isJapaneseLanguage(batch.books[0]),true,
       reason:'original-language eng must not override content language jpn');
   expect(NdlApi.isEnglishLanguage(batch.books[1]),true);
   expect(NdlApi.isEnglishLanguage(batch.books[2]),false);
   expect(NdlApi.isJapaneseLanguage(batch.books[2]),false);
   expect(batch.books[2].languageCode,'jpn eng');
   expect(batch.books[3].languageCode,'');
   expect(NdlApi.isEnglishLanguage(batch.books[3]),false);
 });

 test('SRU home search URL always uses same-origin bounded provider request', () {
   final uri=NdlApi.sruSearchUri(provider:NdlApi.national,title:'日本',
       start:28,count:27);
   expect(uri.path,'/api/ndl-sru');
   expect(uri.queryParameters['dpid'],NdlApi.national);
   expect(uri.queryParameters['title'],'日本');
   expect(uri.queryParameters['idx'],'28');
   expect(uri.queryParameters['cnt'],'27');
 });

}
