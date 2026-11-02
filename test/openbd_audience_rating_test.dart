import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/api/openbd_api.dart';
import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/services/content_safety_service.dart';
const book=Book(id:'9784101010014',isbn:'9784101010014',title:'一般図書',author:'著者',publisher:'出版社',pubDate:'',coverUrl:'');
Map<String,dynamic> record(String code)=>{'summary':{'isbn':book.isbn,'cover':'https://example.com/cover.jpg'},'onix':{'DescriptiveDetail':{'Audience':[{'AudienceCodeType':'22','AudienceCodeValue':code}]}}};
void main(){
 test('explicit adult audience codes are filtered for minors',(){
   for(final code in ['01','02','03']){
     final result=OpenBdApi.enrichRecord(book,record(code));
     expect(result.adultContentFlag,isTrue,reason:code);
     expect(ContentSafetyService.isAdultBook(result),isTrue);
   }
 });
 test('warning alone is not a confirmed 18-plus restriction',(){
   for(final code in ['04','05','06','07']){
     final result=OpenBdApi.enrichRecord(book,record(code));
     expect(result.adultContentFlag,isFalse,reason:code);
     expect(ContentSafetyService.isAdultBook(result),isFalse);
   }
 });
 test('unknown remains visible and existing restriction is preserved',(){
   final unknown=OpenBdApi.enrichRecord(book,{'summary':{'cover':'javascript:alert(1)'}});
   expect(unknown.ageRatingSource,'unknown');expect(unknown.coverUrl,'');
   expect(ContentSafetyService.isAdultBook(unknown),isFalse);
   final restricted=OpenBdApi.enrichRecord(book.copyWith(adultContentFlag:true),record('00'));
   expect(restricted.adultContentFlag,isTrue);
 });

 test('ONIX language role 01 supplies explicitly verified book text language',(){
   final enriched=OpenBdApi.enrichRecord(book,{
     'summary':{'isbn':book.isbn},
     'onix':{'DescriptiveDetail':{'Language':[
       {'LanguageRole':'04','LanguageCode':'eng'},
       {'LanguageRole':'01','LanguageCode':'jpn'},
     ]}}
   });
   expect(enriched.languageCode,'jpn',
       reason:'original language eng must not classify a Japanese edition as English');
 });
 test('bilingual ONIX text language stays bilingual rather than being guessed',(){
   final enriched=OpenBdApi.enrichRecord(book,{
     'onix':{'DescriptiveDetail':{'Language':[
       {'LanguageRole':'01','LanguageCode':'jpn'},
       {'LanguageRole':'01','LanguageCode':'eng'},
     ]}}
   });
   expect(enriched.languageCode,'jpn eng');
 });
 test('existing NDL language always takes priority over ONIX enrich',(){
   final original=book.copyWith(languageCode:'eng');
   final enriched=OpenBdApi.enrichRecord(original,{
     'onix':{'DescriptiveDetail':{'Language':[
       {'LanguageRole':'01','LanguageCode':'jpn'}
     ]}}
   });
   expect(enriched.languageCode,'eng');
 });
}
