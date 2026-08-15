import 'package:attend_ease/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light and dark popup surfaces are distinct and outlined', () {
    final light = AppTheme.lightTheme;
    final dark = AppTheme.darkTheme;

    expect(
      light.snackBarTheme.backgroundColor,
      isNot(dark.snackBarTheme.backgroundColor),
    );
    expect(
      light.dialogTheme.backgroundColor,
      isNot(dark.dialogTheme.backgroundColor),
    );
    expect(
      light.bottomSheetTheme.backgroundColor,
      isNot(dark.bottomSheetTheme.backgroundColor),
    );

    final lightSnackShape =
        light.snackBarTheme.shape! as RoundedRectangleBorder;
    final darkSnackShape = dark.snackBarTheme.shape! as RoundedRectangleBorder;
    final lightDialogShape = light.dialogTheme.shape! as RoundedRectangleBorder;
    final darkDialogShape = dark.dialogTheme.shape! as RoundedRectangleBorder;

    expect(lightSnackShape.side.style, BorderStyle.solid);
    expect(darkSnackShape.side.style, BorderStyle.solid);
    expect(lightDialogShape.side.style, BorderStyle.solid);
    expect(darkDialogShape.side.style, BorderStyle.solid);
    expect(
      lightSnackShape.side.color,
      isNot(light.snackBarTheme.backgroundColor),
    );
    expect(
      darkSnackShape.side.color,
      isNot(dark.snackBarTheme.backgroundColor),
    );
  });

  test('snackbars use phone insets and a desktop width cap', () {
    final compact = AppTheme.withResponsiveOverlays(
      AppTheme.lightTheme,
      400,
    ).snackBarTheme;
    final wide = AppTheme.withResponsiveOverlays(
      AppTheme.lightTheme,
      1200,
    ).snackBarTheme;

    expect(compact.width, isNull);
    expect(compact.insetPadding, AppTheme.snackBarInsetPadding);
    expect(AppTheme.snackBarInsetPadding.bottom, 4);
    expect(wide.width, AppTheme.snackBarMaxWidth);
  });

  test('popup surfaces do not cast elevation shadows', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      expect(theme.snackBarTheme.elevation, 0);
      expect(theme.dialogTheme.elevation, 0);
      expect(theme.bottomSheetTheme.elevation, 0);
      expect(theme.datePickerTheme.elevation, 0);
      expect(theme.popupMenuTheme.elevation, 0);
    }
  });
}
