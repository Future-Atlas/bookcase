import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/services/avatar_url_policy.dart';

void main() {
  const owner = '00000000-0000-4000-8000-000000006901';
  const other = '00000000-0000-4000-8000-000000006902';
  const allowed = 'https://wpoigmywpewrrbudqhgh.supabase.co/storage/v1/object/public/avatars/$owner/avatar.webp?v=123';
  const prod = 'https://jeyxadmkbzgpkveomesz.supabase.co/storage/v1/object/public/avatars/$owner/avatar.jpg';

  test('only managed, owner-specific avatar URLs are loaded', () {
    expect(AvatarUrlPolicy.safeUrl(allowed, ownerId: owner), allowed);
    expect(AvatarUrlPolicy.safeUrl(prod, ownerId: owner), prod);
    expect(AvatarUrlPolicy.image(allowed), isNotNull);
    expect(AvatarUrlPolicy.safeUrl(prod, ownerId: other), isNull);
  });

  test('attacker-controlled hosts and URL tricks are never fetched', () {
    for (final uri in [
      'http://wpoigmywpewrrbudqhgh.supabase.co/storage/v1/object/public/avatars/$owner/avatar.jpg',
      'https://tracker.example/pixel.png',
      'https://wpoigmywpewrrbudqhgh.supabase.co.attacker.example/storage/v1/object/public/avatars/$owner/avatar.jpg',
      'https://attacker@wpoigmywpewrrbudqhgh.supabase.co/storage/v1/object/public/avatars/$owner/avatar.jpg',
      'https://wpoigmywpewrrbudqhgh.supabase.co:8443/storage/v1/object/public/avatars/$owner/avatar.jpg',
      'https://wpoigmywpewrrbudqhgh.supabase.co/storage/v1/object/public/avatars/$owner/avatar.svg',
      'https://wpoigmywpewrrbudqhgh.supabase.co/storage/v1/object/public/avatars/$owner/avatar.jpg?download=1',
      'https://wpoigmywpewrrbudqhgh.supabase.co/storage/v1/object/public/avatars/$owner/avatar.jpg#fragment',
      'https://wpoigmywpewrrbudqhgh.supabase.co/storage/v1/object/public/avatars/$owner/../avatar.jpg',
    ]) {
      expect(AvatarUrlPolicy.safeUrl(uri), isNull, reason: uri);
      expect(AvatarUrlPolicy.image(uri), isNull, reason: uri);
    }
  });

  test('missing avatars retain the original placeholder', () {
    expect(AvatarUrlPolicy.safeUrl(''), isNull);
    expect(AvatarUrlPolicy.safeUrl(null), isNull);
    expect(AvatarUrlPolicy.image(null), isNull);
  });
}
