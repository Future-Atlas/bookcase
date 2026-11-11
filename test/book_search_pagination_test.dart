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
  test('existing 10/5/5 ranking retains unused raw page results',() async{
    final calls=<String>[];
    Future<NdlSearchBatch> fake(BookSearchField field,String term,String provider,int start,int count) async{
      calls.add(field.name+':'+start.toString());
      final rows=List.generate(count,(i)=>candidate(field,start+i));
      return NdlSearchBatch(books:rows,rawCount:count,hasMore:true);
    }
    final repo=BookRepository(fieldFetcher:fake);
    final first=await repo.searchBooksPage('村上春樹',page:1);
    expect(first.books.length,20);expect(first.hasMore,isTrue);
    expect(first.books.take(10).every((b)=>b.author=='村上春樹'),isTrue);
    final second=await repo.searchBooksPage('村上春樹',page:2);
    expect(second.books.length,20);
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
}
