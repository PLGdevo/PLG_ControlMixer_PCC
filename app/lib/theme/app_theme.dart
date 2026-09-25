import 'package:flutter/material.dart';

import 'tokens.dart';

/// Kiểu chữ Barlow (đóng gói trong assets/fonts, không tải qua mạng)
abstract final class AppText {
  static const family = 'Barlow';
  static const _tab = [FontFeature.tabularFigures()];

  static const display = TextStyle(fontFamily: family, fontSize: 32, fontWeight: FontWeight.w800, fontFeatures: _tab);
  static const headline = TextStyle(fontFamily: family, fontSize: 24, fontWeight: FontWeight.w700);
  static const title = TextStyle(fontFamily: family, fontSize: 18, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w400);
  static const label = TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w500);
  static const caption = TextStyle(
      fontFamily: family, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 12 * 0.08);
  static const metric = TextStyle(fontFamily: family, fontSize: 18, fontWeight: FontWeight.w700, fontFeatures: _tab);
}

abstract final class AppTheme {
  static ThemeData dark() => _build(AppTokens.dark, Brightness.dark);
  static ThemeData light() => _build(AppTokens.light, Brightness.light);

  static ThemeData _build(AppTokens t, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: t.accentFill,
      onPrimary: t.onAccentFill,
      primaryContainer: t.accentContainer,
      onPrimaryContainer: t.onAccentContainer,
      secondary: t.accent,
      onSecondary: t.onAccentFill,
      secondaryContainer: t.accentContainer,
      onSecondaryContainer: t.onAccentContainer,
      error: t.bad,
      onError: Colors.white,
      surface: t.surface,
      onSurface: t.text,
      onSurfaceVariant: t.textMuted,
      surfaceContainerHighest: t.surface2,
      surfaceContainerHigh: t.surface2,
      surfaceContainer: t.surface,
      surfaceContainerLow: t.surface,
      surfaceContainerLowest: t.bg,
      outline: t.line,
      outlineVariant: t.line,
    );

    const pill = StadiumBorder();
    final pillLine = StadiumBorder(side: BorderSide(color: t.line));
    WidgetStateProperty<Color?> fg(Color on, Color off) =>
        WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? off : on);

    final text = TextTheme(
      displaySmall: AppText.display.copyWith(color: t.text),
      headlineSmall: AppText.headline.copyWith(color: t.text),
      titleLarge: AppText.headline.copyWith(color: t.text, fontSize: 22),
      titleMedium: AppText.title.copyWith(color: t.text),
      titleSmall: AppText.label.copyWith(color: t.text, fontWeight: FontWeight.w600),
      bodyLarge: AppText.body.copyWith(color: t.text),
      bodyMedium: AppText.body.copyWith(color: t.textBody),
      bodySmall: AppText.caption.copyWith(color: t.textMuted, letterSpacing: 0),
      labelLarge: AppText.label.copyWith(color: t.text),
      labelMedium: AppText.label.copyWith(color: t.textMuted, fontSize: 13),
      labelSmall: AppText.caption.copyWith(color: t.textMuted),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      fontFamily: AppText.family,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      textTheme: text,
      extensions: [t],
      dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 24),
      iconTheme: IconThemeData(color: t.text, size: 24),
      appBarTheme: AppBarTheme(
        backgroundColor: t.surface,
        foregroundColor: t.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: AppText.title.copyWith(color: t.text),
        shape: Border(bottom: BorderSide(color: t.line)),
      ),
      cardTheme: CardThemeData(
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: Gap.xs),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: t.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(pill),
          textStyle: const WidgetStatePropertyAll(AppText.label),
          minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return t.surface2;
            if (s.contains(WidgetState.pressed)) return t.accentFillPressed;
            return t.accentFill;
          }),
          foregroundColor: fg(t.onAccentFill, t.disabled),
          iconColor: fg(t.onAccentFill, t.disabled),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(pillLine),
          side: WidgetStatePropertyAll(BorderSide(color: t.line)),
          textStyle: const WidgetStatePropertyAll(AppText.label),
          minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
          foregroundColor: fg(t.text, t.disabled),
          iconColor: fg(t.text, t.disabled),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(pill),
          textStyle: const WidgetStatePropertyAll(AppText.label),
          foregroundColor: fg(t.accent, t.disabled),
          iconColor: fg(t.accent, t.disabled),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: fg(t.text, t.disabled),
          iconColor: fg(t.text, t.disabled),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: t.accentFill,
        foregroundColor: t.onAccentFill,
        shape: pill,
        elevation: 0,
        highlightElevation: 0,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(pillLine),
          side: WidgetStatePropertyAll(BorderSide(color: t.line)),
          textStyle: const WidgetStatePropertyAll(AppText.label),
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? t.accentContainer : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return t.disabled;
            return s.contains(WidgetState.selected) ? t.onAccentContainer : t.text;
          }),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: t.onAccentFill,
        unselectedLabelColor: t.textMuted,
        labelStyle: AppText.label,
        unselectedLabelStyle: AppText.label,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: ShapeDecoration(color: t.accentFill, shape: pill),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface2,
        labelStyle: AppText.body.copyWith(color: t.textMuted),
        floatingLabelStyle: AppText.body.copyWith(color: t.accent),
        hintStyle: AppText.body.copyWith(color: t.textMuted),
        errorStyle: AppText.label.copyWith(color: t.bad, fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide: BorderSide(color: t.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide: BorderSide(color: t.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide: BorderSide(color: t.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide: BorderSide(color: t.bad),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide: BorderSide(color: t.bad, width: 1.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return t.disabled;
          return s.contains(WidgetState.selected) ? t.onAccentFill : t.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.accentFill : t.surface2),
        trackOutlineColor: WidgetStatePropertyAll(t.line),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.accentFill : Colors.transparent),
        checkColor: WidgetStatePropertyAll(t.onAccentFill),
        side: BorderSide(color: t.textMuted, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.accent : t.textMuted),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: t.accentFill,
        inactiveTrackColor: t.surface2,
        thumbColor: t.accentFill,
        overlayColor: t.accentContainer,
        valueIndicatorColor: t.surface2,
        valueIndicatorTextStyle: AppText.label.copyWith(color: t.text),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
      listTileTheme: ListTileThemeData(
        iconColor: t.textMuted,
        textColor: t.text,
        titleTextStyle: AppText.body.copyWith(color: t.text),
        subtitleTextStyle: AppText.label.copyWith(color: t.textMuted, fontSize: 13),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppText.title.copyWith(color: t.text),
        contentTextStyle: AppText.body.copyWith(color: t.textBody),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: t.line),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.card)),
          side: BorderSide(color: t.line),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.surface2,
        surfaceTintColor: Colors.transparent,
        textStyle: AppText.body.copyWith(color: t.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.field)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.surface2,
        contentTextStyle: AppText.body.copyWith(color: t.text),
        actionTextColor: t.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          side: BorderSide(color: t.line),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.surface2,
        selectedColor: t.accentContainer,
        labelStyle: AppText.label.copyWith(color: t.text),
        side: BorderSide(color: t.line),
        shape: pill,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: t.surface, surfaceTintColor: Colors.transparent),
    );
  }
}
