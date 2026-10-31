/// Officially generated Rakuten affiliate URLs mapped to exact ISBNs.
/// No Rakuten Books API calls, inferred product IDs or unverified search URLs.
/// Insert only URLs generated in the Rakuten Affiliate dashboard after
/// verifying that Sharemarium is an eligible placement destination.
class RakutenAffiliateLinks {
  const RakutenAffiliateLinks._();
  static const Map<String, String> verifiedByIsbn = <String, String>{
    // '9784101010014': 'https://hb.afl.rakuten.co.jp/hgc/...?pc=...',
  };
  static String? forIsbn(String isbn) =>
      verifiedByIsbn[isbn.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase()];
}
