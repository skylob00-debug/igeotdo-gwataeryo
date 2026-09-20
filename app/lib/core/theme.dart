import 'package:flutter/material.dart';

/// 디자인 토큰. 화면 설계(캔버스)와 값을 맞춰 둔다.
///
/// 글자색은 흰 바탕에서 4.5:1 을 넘도록 골랐다. 밝은 주황(#F97316)은
/// 아이콘과 채움에만 쓰고, 글자에는 진한 쪽(#C2410C)을 쓴다.
abstract final class AppColors {
  static const paper = Color(0xFFFFFDF9);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF22242A);
  static const body = Color(0xFF5C606A);
  static const muted = Color(0xFF6B7078); // 흰 바탕에서 5.0:1
  static const line = Color(0xFFEFEAE1);
  static const hairline = Color(0xFFF5F0E8);

  static const accent = Color(0xFFC2410C); // 글자용
  static const accentSolid = Color(0xFFB4470F); // 채움 + 흰 글자
  static const accentIcon = Color(0xFFF97316); // 아이콘·채움 전용
  static const accentSoft = Color(0xFFFFF1E6);

  static const zone = Color(0xFF9A3412); // 보호구역
  static const zoneSoft = Color(0xFFFFF8F2);
  static const chipBg = Color(0xFFF1EEE8);
  static const disabled = Color(0xFFC4C8CE);
}

abstract final class AppRadius {
  static const card = 18.0;
  static const panel = 16.0;
  static const chip = 999.0;
}

ThemeData buildTheme() {
  const font = 'NotoSansKR';
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.paper,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accentSolid,
      brightness: Brightness.light,
      surface: AppColors.paper,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: font,
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: AppColors.ink),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}

/// 카드에 쓰는 부드러운 그림자. 테두리 대신 이것으로 띄운다.
const cardShadow = [
  BoxShadow(color: Color(0x0D22242A), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x0D22242A), blurRadius: 16, offset: Offset(0, 6)),
];

BoxDecoration cardDecoration({double radius = AppRadius.card}) => BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: cardShadow,
    );
