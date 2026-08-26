import 'package:flutter/widgets.dart';

/// Converts a widget's logical width to the physical-pixel width expected by
/// image cache resizing APIs.
int imageCacheWidth(BuildContext context, double logicalWidth) {
  final width = (logicalWidth * MediaQuery.devicePixelRatioOf(context)).ceil();
  return width < 1 ? 1 : width;
}
