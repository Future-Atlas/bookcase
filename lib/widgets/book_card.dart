import 'package:flutter/material.dart';
import '../models/book.dart';

class BookCard extends StatefulWidget {
  final Book book;
  final VoidCallback? onTap;
  final double? width;
  final double height;
  final double coverHeightRatio;
  final double marginRight;
  final double marginBottom;
  final bool showDescription;
  final int descriptionMaxLines;

  const BookCard({
    super.key,
    required this.book,
    this.onTap,
    this.width,
    this.height = 202,
    this.coverHeightRatio = 0.66,
    this.marginRight = 16,
    this.marginBottom = 12,
    this.showDescription = false,
    this.descriptionMaxLines = 2,
  });

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard> {
  bool _isHovered = false;

  String get _displayDescription {
    final text = widget.book.description.trim();
    if (text.isEmpty) {
      return 'あらすじ情報はありません。';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final hasBoundedHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0;
        final cardHeight = hasBoundedHeight
            ? constraints.maxHeight
            : widget.height;

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: widget.width ?? 138,
              height: cardHeight,
              margin: EdgeInsets.only(
                right: widget.marginRight,
                bottom: widget.marginBottom,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: _isHovered ? 0.15 : 0.06,
                    ),
                    blurRadius: _isHovered ? 12 : 6,
                    offset: Offset(0, _isHovered ? 6 : 3),
                  ),
                ],
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: isDarkMode
                      ? const Color(0xFF00E5FF)
                      : const Color(0xFF00BFFF),
                  width: 2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              transform: Matrix4.diagonal3Values(
                _isHovered ? 1.03 : 1.0,
                _isHovered ? 1.03 : 1.0,
                1.0,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The cover fills the whole card. Book information is
                  // overlaid on its lower portion without changing the
                  // information panel's existing height ratio.
                  Hero(
                    tag: 'book-cover-${widget.book.id}',
                    child: Image.network(
                      widget.book.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[300],
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.book,
                            size: 40,
                            color: Colors.grey,
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey[200],
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      widthFactor: 1,
                      heightFactor: 1 - widget.coverHeightRatio,
                      child: ColoredBox(
                        color: Theme.of(context).cardColor,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              Text(
                                widget.book.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (!widget.showDescription) const Spacer(),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.star,
                                    color: Colors.amber,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    widget.book.ratingAvg.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              if (widget.showDescription) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _displayDescription,
                                  maxLines: widget.descriptionMaxLines,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[700],
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
