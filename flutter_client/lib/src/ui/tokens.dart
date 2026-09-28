import 'package:flutter/material.dart';

/// RDesk design tokens. Light: cool grey canvas with white cards; dark: layered
/// graphite. Brand blue comes from the app icon; the icon's orange is reserved
/// for power actions such as remote wake.
@immutable
class RdPalette extends ThemeExtension<RdPalette> {
  final Color canvas, surface, surfaceMuted, border, divider;
  final Color ink, inkSecondary, inkTertiary;
  final Color brand, brandSoft, brandInk;
  final Color power, powerSoft;
  final Color online, onlineSoft, warning, warningSoft, danger, dangerSoft;
  final Color sidebar, sidebarSelected;

  const RdPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.divider,
    required this.ink,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.brand,
    required this.brandSoft,
    required this.brandInk,
    required this.power,
    required this.powerSoft,
    required this.online,
    required this.onlineSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.sidebar,
    required this.sidebarSelected,
  });

  static const light = RdPalette(
    canvas: Color(0xFFF3F5F9),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF6F7FA),
    border: Color(0xFFE4E8EF),
    divider: Color(0xFFEEF0F4),
    ink: Color(0xFF111827),
    inkSecondary: Color(0xFF596274),
    inkTertiary: Color(0xFF8A93A3),
    brand: Color(0xFF2B6BFF),
    brandSoft: Color(0xFFEAF1FF),
    brandInk: Color(0xFF1D4FD8),
    power: Color(0xFFF26A1B),
    powerSoft: Color(0xFFFFF1E8),
    online: Color(0xFF16A34A),
    onlineSoft: Color(0xFFE7F6EC),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFFF6E5),
    danger: Color(0xFFDC3545),
    dangerSoft: Color(0xFFFDECEE),
    sidebar: Color(0xFFF7F8FB),
    sidebarSelected: Color(0xFFE6EDFD),
  );

  static const dark = RdPalette(
    canvas: Color(0xFF0E1015),
    surface: Color(0xFF171A21),
    surfaceMuted: Color(0xFF1D2129),
    border: Color(0xFF2A2F3A),
    divider: Color(0xFF232731),
    ink: Color(0xFFF1F3F7),
    inkSecondary: Color(0xFFA6AEBC),
    inkTertiary: Color(0xFF6F7788),
    brand: Color(0xFF5B8CFF),
    brandSoft: Color(0xFF1C2842),
    brandInk: Color(0xFF9DB8FF),
    power: Color(0xFFFF8A45),
    powerSoft: Color(0xFF3A2416),
    online: Color(0xFF34C66A),
    onlineSoft: Color(0xFF15301F),
    warning: Color(0xFFF5A524),
    warningSoft: Color(0xFF33270F),
    danger: Color(0xFFFF6B77),
    dangerSoft: Color(0xFF3A1A1F),
    sidebar: Color(0xFF12151B),
    sidebarSelected: Color(0xFF1F2A44),
  );

  static RdPalette of(BuildContext context) =>
      Theme.of(context).extension<RdPalette>() ?? light;

  @override
  RdPalette copyWith() => this;

  @override
  RdPalette lerp(RdPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return RdPalette(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      border: c(border, other.border),
      divider: c(divider, other.divider),
      ink: c(ink, other.ink),
      inkSecondary: c(inkSecondary, other.inkSecondary),
      inkTertiary: c(inkTertiary, other.inkTertiary),
      brand: c(brand, other.brand),
      brandSoft: c(brandSoft, other.brandSoft),
      brandInk: c(brandInk, other.brandInk),
      power: c(power, other.power),
      powerSoft: c(powerSoft, other.powerSoft),
      online: c(online, other.online),
      onlineSoft: c(onlineSoft, other.onlineSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      sidebar: c(sidebar, other.sidebar),
      sidebarSelected: c(sidebarSelected, other.sidebarSelected),
    );
  }
}

/// Spacing, radius and motion scale shared by every screen.
abstract final class Rd {
  static const double s4 = 4, s8 = 8, s12 = 12, s16 = 16, s20 = 20;
  static const double s24 = 24, s32 = 32, s40 = 40;
  static const double radiusSm = 8, radius = 12, radiusLg = 16, radiusXl = 20;
  static const double pagePadding = 20, pagePaddingDesktop = 32;
  static const double contentMaxWidth = 960;
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 240);
  static const Curve ease = Cubic(0.2, 0, 0, 1);
}
