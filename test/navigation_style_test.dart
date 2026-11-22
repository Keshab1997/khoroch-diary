// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';

void main() {
  test('navigation highlights the selected tab with a readable green pill', () {
    final theme = AppTheme.light().navigationBarTheme;
    expect(theme.indicatorColor, AppColors.primaryGreen);
    expect(theme.indicatorShape, isA<StadiumBorder>());
    expect(
      theme.iconTheme!.resolve({WidgetState.selected})!.color,
      AppColors.onPrimary,
    );
    expect(
      theme.iconTheme!.resolve(<WidgetState>{})!.color,
      AppColors.softText,
    );
    expect(
      theme.labelTextStyle!.resolve({WidgetState.selected})!.color,
      AppColors.primaryGreen,
    );
    expect(theme.labelBehavior, NavigationDestinationLabelBehavior.alwaysShow);
  });
}
