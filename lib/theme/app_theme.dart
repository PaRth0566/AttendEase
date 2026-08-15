import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_dimens.dart';
import 'app_page_transition.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF2563EB);

  static const PageTransitionsTheme _pageTransitionsTheme =
      PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
        },
      );

  /// The app's text font, bundled in `assets/fonts/` and declared in
  /// `pubspec.yaml`.
  ///
  /// This MUST stay a bundled font rather than a runtime-fetched one. With no
  /// `fontFamily` set, Flutter falls back to Roboto — and the CanvasKit web
  /// renderer does not ship Roboto, it downloads it from fonts.gstatic.com on
  /// first paint. When that request was slow, blocked or offline the web build
  /// laid out every label at the right size and then painted no glyphs at all,
  /// so the site rendered as icons and empty boxes. Bundling removes the
  /// network from the text-rendering path entirely.
  static const String fontFamily = 'Inter';

  /// Stamps [fontFamily] onto a component-theme text style.
  ///
  /// `ThemeData.fontFamily` only reaches `textTheme`/`primaryTextTheme`. Every
  /// raw `TextStyle` handed to a *component* theme (appBarTheme, dialogTheme,
  /// snackBarTheme, chipTheme, button `textStyle`, ...) keeps `fontFamily: null`,
  /// which resolves to Roboto — a font CanvasKit fetches from fonts.gstatic.com
  /// rather than ships. When that fetch is slow or blocked the web build lays
  /// text out correctly and paints no glyphs, so buttons and dialogs render
  /// blank.
  ///
  /// Every `TextStyle` in this file goes through here, `textTheme` included.
  /// The `textTheme` entries are already covered by `ThemeData.fontFamily`, but
  /// routing them through anyway leaves the file with one uniform rule and no
  /// "which of these matter?" judgement call at the next edit.
  static TextStyle _f(TextStyle style) =>
      style.copyWith(fontFamily: fontFamily);

  /// Max width of a floating `SnackBar`.
  ///
  /// Floating snackbars have no intrinsic max width, so on a 1568 px desktop
  /// viewport the chip measured 1538 px — a band across the whole page, painted
  /// over the content it was meant to annotate. Phones use responsive insets;
  /// this cap keeps the same component compact on larger windows.
  static const double snackBarMaxWidth = 480;

  /// Floating snackbar spacing used on compact layouts. Desktop layouts use
  /// [snackBarMaxWidth] instead so messages stay readable without becoming a
  /// full-width band.
  static const EdgeInsets snackBarInsetPadding = EdgeInsets.fromLTRB(
    16,
    8,
    16,
    4,
  );

  /// Applies the one responsive overlay rule that a static [ThemeData] cannot
  /// express: phones need insets, while larger windows benefit from a capped
  /// snackbar chip. All other component styling remains the selected theme.
  static ThemeData withResponsiveOverlays(ThemeData theme, double width) {
    final bool compact = width < 600;
    return theme.copyWith(
      snackBarTheme: theme.snackBarTheme.copyWith(
        width: compact ? null : snackBarMaxWidth,
        insetPadding: compact ? snackBarInsetPadding : null,
      ),
    );
  }

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    brightness: Brightness.light,
    primaryColor: primaryBlue,
    pageTransitionsTheme: _pageTransitionsTheme,
    scaffoldBackgroundColor: Colors.white,
    colorScheme: const ColorScheme.light(
      primary: primaryBlue,
      secondary: primaryBlue,
      surface: Colors.white,
      onSurface: Color(0xFF1E293B),
      outline: Color(0xFFE2E8F0),
    ),
    extensions: const [AppColors.light],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
      titleTextStyle: _f(
        const TextStyle(
          color: Color(0xFF1E293B),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
    cardColor: const Color(0xFFF2F4FF),
    dividerColor: const Color(0xFFE2E8F0),
    textTheme: TextTheme(
      displaySmall: _f(
        const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E293B),
          letterSpacing: -0.5,
        ),
      ),
      headlineMedium: _f(
        const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E293B),
        ),
      ),
      headlineSmall: _f(
        const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E293B),
        ),
      ),
      titleLarge: _f(
        const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
      titleMedium: _f(
        const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
      titleSmall: _f(
        const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
      bodyLarge: _f(const TextStyle(fontSize: 16, color: Color(0xFF1E293B))),
      bodyMedium: _f(const TextStyle(fontSize: 14, color: Color(0xFF475569))),
      bodySmall: _f(const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      labelLarge: _f(
        const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: const Color(0xFFF2F4FF),
      shape: RoundedRectangleBorder(
        borderRadius: AppDimens.brMd,
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: const RoundedRectangleBorder(borderRadius: AppDimens.brMd),
        textStyle: _f(
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryBlue,
        side: const BorderSide(color: primaryBlue, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: const RoundedRectangleBorder(borderRadius: AppDimens.brMd),
        textStyle: _f(
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryBlue,
        textStyle: _f(
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: AppDimens.brMd,
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppDimens.brMd,
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppDimens.brMd,
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppDimens.brMd,
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppDimens.brMd,
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
      ),
      labelStyle: _f(const TextStyle(color: Color(0xFF64748B))),
      hintStyle: _f(const TextStyle(color: Color(0xFF94A3B8))),
    ),
    chipTheme: ChipThemeData(
      shape: const RoundedRectangleBorder(borderRadius: AppDimens.brSm),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
      backgroundColor: const Color(0xFFF8FAFC),
      selectedColor: const Color(0xFFDBEAFE),
      labelStyle: _f(
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFFF4F5F7),
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDimens.brLg,
        side: BorderSide(color: Color(0xFFC7CCD4)),
      ),
      titleTextStyle: _f(
        const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E293B),
        ),
      ),
      contentTextStyle: _f(
        const TextStyle(fontSize: 14, color: Color(0xFF475569)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFFF4F5F7),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppDimens.rXl),
        side: BorderSide(color: Color(0xFFC7CCD4)),
      ),
    ),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: Color(0xFFF4F5F7),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      headerBackgroundColor: Color(0xFFECEFF3),
      headerForegroundColor: Color(0xFF1E293B),
      dividerColor: Color(0xFFC7CCD4),
      shape: RoundedRectangleBorder(
        borderRadius: AppDimens.brLg,
        side: BorderSide(color: Color(0xFFC7CCD4)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDimens.brMd,
        side: BorderSide(color: Color(0xFFC7CCD4)),
      ),
      backgroundColor: const Color(0xFFF1F3F5),
      actionTextColor: primaryBlue,
      contentTextStyle: _f(
        const TextStyle(color: Color(0xFF1E293B), fontSize: 14),
      ),
      insetPadding: snackBarInsetPadding,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFFF4F5F7),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDimens.brMd,
        side: BorderSide(color: Color(0xFFC7CCD4)),
      ),
      textStyle: _f(const TextStyle(color: Color(0xFF1E293B), fontSize: 14)),
    ),
    tooltipTheme: TooltipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: _f(const TextStyle(color: Color(0xFF1E293B), fontSize: 12)),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F5),
        borderRadius: AppDimens.brSm,
        border: Border.all(color: const Color(0xFFC7CCD4)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 0,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return _f(
            const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primaryBlue,
            ),
          );
        }
        return _f(const TextStyle(fontSize: 12, color: Color(0xFF64748B)));
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primaryBlue);
        }
        return const IconThemeData(color: Color(0xFF64748B));
      }),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryBlue,
      linearTrackColor: Color(0xFFE2E8F0),
      linearMinHeight: 6,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE2E8F0),
      thickness: 1,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    brightness: Brightness.dark,
    primaryColor: primaryBlue,
    pageTransitionsTheme: _pageTransitionsTheme,
    scaffoldBackgroundColor: Colors.black,
    colorScheme: const ColorScheme.dark(
      primary: primaryBlue,
      secondary: primaryBlue,
      surface: Color(0xFF121212),
      onSurface: Colors.white,
      outline: Color(0xFF2A2A2A),
    ),
    extensions: const [AppColors.dark],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.black,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: _f(
        const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
    cardColor: const Color(0xFF121212),
    dividerColor: const Color(0xFF2A2A2A),
    textTheme: TextTheme(
      displaySmall: _f(
        const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
      ),
      headlineMedium: _f(
        const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      headlineSmall: _f(
        const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      titleLarge: _f(
        const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      titleMedium: _f(
        const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      titleSmall: _f(
        const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      bodyLarge: _f(const TextStyle(fontSize: 16, color: Colors.white)),
      bodyMedium: _f(const TextStyle(fontSize: 14, color: Colors.white70)),
      bodySmall: _f(const TextStyle(fontSize: 12, color: Colors.white54)),
      labelLarge: _f(
        const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: const Color(0xFF121212),
      shape: RoundedRectangleBorder(
        borderRadius: AppDimens.brMd,
        side: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: const RoundedRectangleBorder(borderRadius: AppDimens.brMd),
        textStyle: _f(
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryBlue,
        side: const BorderSide(color: primaryBlue, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: const RoundedRectangleBorder(borderRadius: AppDimens.brMd),
        textStyle: _f(
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryBlue,
        textStyle: _f(
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: AppDimens.brMd,
        borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppDimens.brMd,
        borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppDimens.brMd,
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppDimens.brMd,
        borderSide: const BorderSide(color: Color(0xFFF87171)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppDimens.brMd,
        borderSide: const BorderSide(color: Color(0xFFF87171), width: 2),
      ),
      labelStyle: _f(const TextStyle(color: Colors.white54)),
      hintStyle: _f(const TextStyle(color: Colors.white38)),
    ),
    chipTheme: ChipThemeData(
      shape: const RoundedRectangleBorder(borderRadius: AppDimens.brSm),
      side: const BorderSide(color: Color(0xFF2A2A2A)),
      backgroundColor: const Color(0xFF1E1E1E),
      selectedColor: const Color(0xFF1D3461),
      labelStyle: _f(
        const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF181A1D),
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDimens.brLg,
        side: BorderSide(color: Color(0xFF3D4148)),
      ),
      titleTextStyle: _f(
        const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      contentTextStyle: _f(
        const TextStyle(fontSize: 14, color: Colors.white70),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF181A1D),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppDimens.rXl),
        side: BorderSide(color: Color(0xFF3D4148)),
      ),
    ),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: Color(0xFF181A1D),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      headerBackgroundColor: Color(0xFF202226),
      headerForegroundColor: Colors.white,
      dividerColor: Color(0xFF3D4148),
      shape: RoundedRectangleBorder(
        borderRadius: AppDimens.brLg,
        side: BorderSide(color: Color(0xFF3D4148)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDimens.brMd,
        side: BorderSide(color: Color(0xFF484D55)),
      ),
      backgroundColor: const Color(0xFF202226),
      actionTextColor: const Color(0xFF8CE0B2),
      contentTextStyle: _f(const TextStyle(color: Colors.white, fontSize: 14)),
      insetPadding: snackBarInsetPadding,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFF181A1D),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDimens.brMd,
        side: BorderSide(color: Color(0xFF3D4148)),
      ),
      textStyle: _f(const TextStyle(color: Colors.white, fontSize: 14)),
    ),
    tooltipTheme: TooltipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: _f(const TextStyle(color: Colors.white, fontSize: 12)),
      decoration: BoxDecoration(
        color: const Color(0xFF202226),
        borderRadius: AppDimens.brSm,
        border: Border.all(color: const Color(0xFF484D55)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.black,
      elevation: 0,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return _f(
            const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primaryBlue,
            ),
          );
        }
        return _f(const TextStyle(fontSize: 12, color: Colors.white54));
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primaryBlue);
        }
        return const IconThemeData(color: Colors.white54);
      }),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryBlue,
      linearTrackColor: Color(0xFF2A2A2A),
      linearMinHeight: 6,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF2A2A2A),
      thickness: 1,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}
