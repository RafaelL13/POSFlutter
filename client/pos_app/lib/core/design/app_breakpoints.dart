import 'package:flutter/widgets.dart';

enum AppLayoutSize { compact, medium, expanded }

abstract final class AppBreakpoints {
  static const medium = 600.0;
  static const expanded = 900.0;

  static AppLayoutSize ofWidth(double width) => switch (width) {
    < medium => AppLayoutSize.compact,
    < expanded => AppLayoutSize.medium,
    _ => AppLayoutSize.expanded,
  };

  static AppLayoutSize of(BuildContext context) =>
      ofWidth(MediaQuery.sizeOf(context).width);
}
