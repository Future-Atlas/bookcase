import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../models/post.dart';
import '../services/content_safety_service.dart';
import '../services/supabase_service.dart';
import 'book_cover_image.dart';
import 'star_rating_slider.dart';

const int _postCommentMaxLength = 1000;

/// Keep the existing entrypoint for read and edit actions, but open a full
/// route rather than an AlertDialog. This lets the keyboard resize the page.
Future<bool> showPostComposerDialog({
  required BuildContext context,
  required Book book,
  Post? existingPost,
}) async {
  final service = Provider.of<SupabaseService>(context, listen: false);
  if (ContentSafetyService.isAdultBook(book) &&
      !await service.canViewAdultContent()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この書籍は18歳未満の利用者には表示・投稿できません。')),
      );
    }
    return false;
  }
  if (!context.mounted) return false;

  final posted = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => _PostComposerPage(
        book: book,
        existingPost: existingPost,
        service: service,
      ),
    ),
  );
  if (posted == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(existingPost != null ? '投稿を編集しました' : '投稿が完了しました！')),
    );
  }
  return posted ?? false;
}

class _PostComposerPage extends StatefulWidget {
  const _PostComposerPage({
    required this.book,
    required this.existingPost,
    required this.service,
  });

  final Book book;
  final Post? existingPost;
  final SupabaseService service;

  @override
  State<_PostComposerPage> createState() => _PostComposerPageState();
}

class _PostComposerPageState extends State<_PostComposerPage> {
  late final TextEditingController commentController;
  late double rating;
  late bool hasSelectedRating;
  late bool isSpoiler;
  bool isSubmitting = false;

  bool get isEditing => widget.existingPost != null;

  @override
  void initState() {
    super.initState();
    rating = widget.existingPost?.rating ?? 0.0;
    hasSelectedRating = widget.existingPost != null;
    isSpoiler = widget.existingPost?.hasSpoiler ?? false;
    commentController = TextEditingController(
      text: widget.existingPost?.reviewText ?? '',
    );
  }

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (isSubmitting) return;
    final review = commentController.text.trim();
    if (!hasSelectedRating) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('評価が付いていないので、投稿できません')),
      );
      return;
    }
    if (review.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('感想が未入力なので、投稿できません')),
      );
      return;
    }

    setState(() => isSubmitting = true);
    bool success;
    try {
      success = isEditing
          ? await widget.service.updateOwnPost(
              post: widget.existingPost!,
              rating: rating,
              comment: review,
              isSpoiler: isSpoiler,
            )
          : await widget.service.createPost(
              book: widget.book,
              rating: rating,
              comment: review,
              isSpoiler: isSpoiler,
            );
    } catch (e) {
      success = false;
      // Errors from preflight checks must never be left opaque.
      widget.service.lastPostSaveError ??= '保存処理中に予期しないエラーが発生しました。';
    }
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.service.lastPostSaveError ??
                '保存できませんでした。通信状態を確認してもう一度お試しください。',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: const Color(0xFFE9E9E9),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFFE9E9E9),
        foregroundColor: const Color(0xFFFF3B30),
        title: Text(
          isEditing ? '投稿を編集' : '読了の投稿',
          style: const TextStyle(
            color: Color(0xFFFF3B30),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 32, 16, compact ? 16 : 32, 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 88,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 88,
                              height: 126,
                              color: Colors.grey[350],
                              child: BookCoverImage(book: widget.book),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.book.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SpoilerButton(
                              label: 'ネタバレなし投稿',
                              selected: !isSpoiler,
                              onPressed: () => setState(() => isSpoiler = false),
                            ),
                            _SpoilerButton(
                              label: 'ネタバレあり投稿',
                              selected: isSpoiler,
                              onPressed: () => setState(() => isSpoiler = true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  StarRatingSlider(
                    value: rating,
                    onChanged: (score) => setState(() {
                      rating = score;
                      hasSelectedRating = true;
                    }),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFD2D2D2),
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      key: const Key('post-review-text-field'),
                      controller: commentController,
                      maxLength: _postCommentMaxLength,
                      minLines: 6,
                      maxLines: 10,
                      scrollPadding: const EdgeInsets.only(bottom: 120),
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(color: Colors.black87),
                      decoration: const InputDecoration(
                        hintText: '例：印象に残った場面、その理由、読後に考えたことなどを自分の言葉で書いてみましょう',
                        hintStyle: TextStyle(color: Colors.black54),
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1000字以内で、自由に感想を記入してください。特定の人物や組織に対する誹謗中傷や個人情報を記載した場合、投稿が削除されることがあります。',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(
                          'キャンセル',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF3B30),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: isSubmitting ? null : _submit,
                        child: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(isEditing ? '保存する' : '投稿する'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpoilerButton extends StatelessWidget {
  const _SpoilerButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: selected ? const Color(0xFFFF1F1F) : Colors.white70,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label),
    );
  }
}
