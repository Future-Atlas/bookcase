import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/api/ndl_api.dart';
import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/repositories/book_repository.dart';

Book candidate(BookSearchField field,int i){
  final isbn=(1000000000+field.index*10000+i).toString();
  return Book(id:isbn,isbn:isbn,
    title:field==BookSearchField.title ? '村上春樹の本$i' : '別の本$i',
    author:field==BookSearchField.author ? '村上春樹' : '別の著者',
    publisher:field==BookSearchField.publisher ? '村上春樹出版' : '出版社',
    pubDate:'',coverUrl:'');
}

void main(){
  test('4/3/3 ranking retains unused raw page results',() async{
    final calls=<String>[];
    Future<NdlSearchBatch> fake(BookSearchField field,String term,String provider,int start,int count) async{
      calls.add(field.name+':'+start.toString());
      final rows=List.generate(count,(i)=>candidate(field,start+i));
      return NdlSearchBatch(books:rows,rawCount:count,hasMore:true);
    }
    final repo=BookRepository(fieldFetcher:fake);
    final first=await repo.searchBooksPage('村上春樹',page:1);
    expect(first.books.length,10);expect(first.hasMore,isTrue);
    expect(first.books.take(4).every((b)=>b.author=='村上春樹'),isTrue);
    final second=await repo.searchBooksPage('村上春樹',page:2);
    expect(second.books.length,10);
    final ids1=first.books.map((b)=>b.id).toSet();
    final ids2=second.books.map((b)=>b.id).toSet();
    expect(ids1.intersection(ids2),isEmpty);
    expect(calls.length,3);
  });
  test('secondary fields being empty does not end primary field pagination',() async{
    Future<NdlSearchBatch> fake(BookSearchField field,String term,String provider,int start,int count) async{
      if(field!=BookSearchField.author){
        return const NdlSearchBatch(books:[],rawCount:0,hasMore:false);
      }
      return NdlSearchBatch(
        books:List.generate(count,(i)=>candidate(field,start+i)),
        rawCount:count,hasMore:true);
    }
    final repo=BookRepository(fieldFetcher:fake);
    final first=await repo.searchBooksPage('村上春樹',page:1);
    final second=await repo.searchBooksPage('村上春樹',page:2);
    expect(first.books.isNotEmpty,isTrue);
    expect(first.hasMore,isTrue);
    expect(second.books.isNotEmpty,isTrue);
    expect(first.books.map((b)=>b.id).toSet()
      .intersection(second.books.map((b)=>b.id).toSet()),isEmpty);
  });
  test('temporary NDL outage stays retryable and never counts as no matches', () async {
    var fail = true;
    Future<NdlSearchBatch> fake(
      BookSearchField field, String term, String provider, int start, int count,
    ) async {
      if (fail) {
        return const NdlSearchBatch(
          books: [], rawCount: 0, hasMore: false,
          temporarilyUnavailable: true,
        );
      }
      return NdlSearchBatch(
        books: List.generate(count, (i) => candidate(field, start + i)),
        rawCount: count, hasMore: true,
      );
    }
    final repo = BookRepository(fieldFetcher: fake);
    final outage = await repo.searchBooksPage('村上春樹', page: 1);
    expect(outage.books, isEmpty);
    expect(outage.temporarilyUnavailable, isTrue);
    expect(outage.hasMore, isTrue);

    fail = false;
    final retried = await repo.searchBooksPage('村上春樹', page: 1);
    expect(retried.temporarilyUnavailable, isFalse);
    expect(retried.books, isNotEmpty);
  });

  test('ISBN-less first windows do not claim the whole query has no matches', () async {
    var received = 0;
    Future<NdlSearchBatch> sparse(
      BookSearchField field, String term, String provider, int start, int count,
    ) async {
      received++;
      // A legitimate NDL window can be full but contain no displayable ISBN.
      if (start <= 61) {
        return NdlSearchBatch(
          books: [], rawCount: count, hasMore: true,
        );
      }
      return NdlSearchBatch(
        books: [candidate(field, start)],
        rawCount: count, hasMore: true,
      );
    }
    final repo = BookRepository(fieldFetcher: sparse);
    final first = await repo.searchBooksPage('芥川', page: 1, count: 10);
    expect(first.books, isEmpty);
    expect(first.temporarilyUnavailable, isFalse);
    expect(first.hasMore, isTrue,
      reason: 'A result page lacking ISBNs must allow further pagination');

    final second = await repo.searchBooksPage('芥川', page: 2, count: 10);
    expect(second.books, isNotEmpty);
    expect(received, greaterThan(3));
  });

}
