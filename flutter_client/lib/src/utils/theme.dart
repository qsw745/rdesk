import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ui/tokens.dart';
import 'windows_ui_font.dart';

class AppTheme {
  // Legacy names kept for existing call sites; values follow the RDesk palette.
  static const Color primaryBlue = Color(0xFF2B6BFF);
  static const Color deepBlue = Color(0xFF1D4FD8);
  static const Color accentPurple = Color(0xFF6D5BD0);
  static const Color successGreen = Color(0xFF16A34A);
  static const Color warningAmber = Color(0xFFD97706);
  static const Color errorRed = Color(0xFFDC3545);
  static const Color surfaceLight = Color(0xFFF3F5F9);
  static const Color surfaceDark = Color(0xFF0E1015);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF596274);

  /// Screenshot tooling sets this to a loaded family; production leaves it null.
  static String? debugFontFamily;

  static const SystemUiOverlayStyle lightStatusBarStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemStatusBarContrastEnforced: false,
  );

  static const SystemUiOverlayStyle darkStatusBarStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );

  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF3A7BFF), Color(0xFF1D4FD8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient headerGradient = brandGradient;

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFFFA84E), Color(0xFFF26A1B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get lightTheme => _build(RdPalette.light, Brightness.light);
  static ThemeData get darkTheme => _build(RdPalette.dark, Brightness.dark);

  static String? get _family =>
      debugFontFamily ??
      (defaultTargetPlatform == TargetPlatform.windows
          ? (WindowsUiFont.isLoaded
              ? WindowsUiFont.family
              : 'Microsoft YaHei UI')
          : null);

  static TextTheme _text(RdPalette p) {
    TextStyle s(double size, FontWeight w, Color c, [double h = 1.4]) =>
        TextStyle(
            fontSize: size,
            fontWeight: w,
            color: c,
            height: h,
            letterSpacing: 0,
            fontFamily: _family);
    return TextTheme(
      displaySmall: s(30, FontWeight.w700, p.ink, 1.2),
      headlineMedium: s(26, FontWeight.w700, p.ink, 1.25),
      headlineSmall: s(22, FontWeight.w700, p.ink, 1.3),
      titleLarge: s(19, FontWeight.w700, p.ink, 1.3),
      titleMedium: s(16, FontWeight.w600, p.ink),
      titleSmall: s(14, FontWeight.w600, p.ink),
      bodyLarge: s(16, FontWeight.w400, p.ink, 1.5),
      bodyMedium: s(14.5, FontWeight.w400, p.ink, 1.5),
      bodySmall: s(13, FontWeight.w400, p.inkSecondary, 1.45),
      labelLarge: s(14.5, FontWeight.w600, p.ink),
      labelMedium: s(13, FontWeight.w500, p.inkSecondary),
      labelSmall: s(12, FontWeight.w500, p.inkTertiary),
    );
  }

  static ThemeData _build(RdPalette p, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final text = _text(p);
    final scheme = ColorScheme.fromSeed(
      seedColor: p.brand,
      brightness: brightness,
    ).copyWith(
      primary: p.brand,
      onPrimary: Colors.white,
      primaryContainer: p.brandSoft,
      onPrimaryContainer: p.brandInk,
      secondary: p.brandInk,
      tertiary: p.power,
      error: p.danger,
      errorContainer: p.dangerSoft,
      surface: p.surface,
      onSurface: p.ink,
      onSurfaceVariant: p.inkSecondary,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surfaceMuted,
      surfaceContainer: p.surfaceMuted,
      surfaceContainerHigh: p.surfaceMuted,
      surfaceContainerHighest: p.divider,
      outline: p.border,
      outlineVariant: p.divider,
    );
    final radius = BorderRadius.circular(Rd.radius);
    final small = BorderRadius.circular(Rd.radiusSm + 2);
    final buttonText = text.labelLarge!;
    OutlineInputBorder field(Color color, [double width = 1]) =>
        OutlineInputBorder(
            borderRadius: small,
            borderSide: BorderSide(color: color, width: width));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: _family,
      fontFamilyFallback: defaultTargetPlatform == TargetPlatform.windows
          ? const ['Microsoft YaHei UI', 'Segoe UI', 'Microsoft YaHei']
          : null,
      textTheme: text,
      primaryTextTheme: text,
      extensions: [p],
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      dividerColor: p.divider,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.inkSecondary, size: 22),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: p.canvas,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: dark ? darkStatusBarStyle : lightStatusBarStyle,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: p.ink, size: 22),
        actionsIconTheme: IconThemeData(color: p.inkSecondary, size: 22),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: radius, side: BorderSide(color: p.border)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.inkSecondary,
        textColor: p.ink,
        titleTextStyle: text.bodyLarge!.copyWith(fontWeight: FontWeight.w500),
        subtitleTextStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 12,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.divider,
          disabledForegroundColor: p.inkTertiary,
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: small),
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.brand,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: small),
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(borderRadius: small),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.brand,
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: small),
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.inkSecondary,
          shape: RoundedRectangleBorder(borderRadius: small),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceMuted,
        isDense: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: field(p.border),
        enabledBorder: field(p.border),
        focusedBorder: field(p.brand, 1.5),
        errorBorder: field(p.danger),
        focusedErrorBorder: field(p.danger, 1.5),
        disabledBorder: field(p.divider),
        hintStyle: text.bodyMedium!.copyWith(color: p.inkTertiary),
        labelStyle: text.bodyMedium!.copyWith(color: p.inkSecondary),
        floatingLabelStyle: text.bodySmall!.copyWith(color: p.brand),
        prefixIconColor: p.inkTertiary,
        suffixIconColor: p.inkTertiary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.brandSoft,
        secondarySelectedColor: p.brandSoft,
        side: BorderSide(color: p.border),
        labelStyle: text.labelMedium!.copyWith(color: p.inkSecondary),
        secondaryLabelStyle: text.labelMedium!.copyWith(color: p.brandInk),
        shape: const StadiumBorder(),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : p.inkTertiary),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.brand : p.divider),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.brand : p.border),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.brand : Colors.transparent),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: p.surfaceMuted,
          selectedBackgroundColor: p.surface,
          selectedForegroundColor: p.ink,
          foregroundColor: p.inkSecondary,
          side: BorderSide(color: p.border),
          textStyle: text.labelMedium,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? p.brand : p.inkTertiary)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelSmall!
            .copyWith(
                fontSize: 11.5,
                fontWeight: s.contains(WidgetState.selected)
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: s.contains(WidgetState.selected)
                    ? p.brand
                    : p.inkTertiary)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.12),
        shape: RoundedRectangleBorder(
            borderRadius: radius, side: BorderSide(color: p.border)),
        textStyle: text.bodyMedium,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: radius, side: BorderSide(color: p.border))),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.18),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rd.radiusXl)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium!.copyWith(color: p.inkSecondary),
      ),
      // Existing sheets paint their own surface and drag handle.
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(Rd.radiusXl))),
        clipBehavior: Clip.antiAlias,
        showDragHandle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: dark ? p.surfaceMuted : p.ink,
        contentTextStyle: text.bodyMedium!.copyWith(color: Colors.white),
        actionTextColor: dark ? p.brandInk : const Color(0xFF9DB8FF),
        shape: RoundedRectangleBorder(borderRadius: small),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
            color: dark ? p.surfaceMuted : p.ink,
            borderRadius: BorderRadius.circular(6)),
        textStyle: text.labelSmall!.copyWith(color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
          color: p.brand,
          linearTrackColor: p.divider,
          circularTrackColor: p.divider),
      tabBarTheme: TabBarThemeData(
        labelColor: p.brand,
        unselectedLabelColor: p.inkSecondary,
        indicatorColor: p.brand,
        dividerColor: p.divider,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.border),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
