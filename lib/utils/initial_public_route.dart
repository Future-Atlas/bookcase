/// Flutter's default hash routing otherwise ignores a clean /book/... URL.
/// Keep OAuth fragments and unrelated shell routes on their existing path.
String? initialPublicRoute(Uri uri) {
  final route = uri.fragment.startsWith('/') ? Uri.tryParse(uri.fragment) : uri;
  if (route == null) return null;
  final path = route.path.replaceFirst(RegExp(r'/$'), '');
  if (RegExp(r'^/book/(\d{13}|\d{9}[\dXx])$').hasMatch(path) ||
      path == '/posts' ||
      RegExp(r'^/posts/[0-9a-fA-F-]{36}$').hasMatch(path)) {
    return path;
  }
  return null;
}
