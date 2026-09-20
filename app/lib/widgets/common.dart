import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 분류·상태를 나타내는 알약 라벨.
class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    this.color = AppColors.accent,
    this.background = AppColors.accentSoft,
    this.bold = false,
  });

  final String text;
  final Color color;
  final Color background;
  final bool bold;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      );
}

/// 화면 위쪽의 라벨 + 큰 제목.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.label,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String label;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 1.1,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 23,
                height: 1.3,
                letterSpacing: -0.4,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 7),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: AppColors.muted,
                ),
              ),
            ],
          ],
        ),
      );
}

/// 저장(즐겨찾기) 토글.
class SaveButton extends StatelessWidget {
  const SaveButton({
    super.key,
    required this.saved,
    required this.onPressed,
    this.size = 20,
  });

  final bool saved;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onPressed,
        iconSize: size,
        visualDensity: VisualDensity.compact,
        tooltip: saved ? '저장 해제' : '저장',
        icon: Icon(
          saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          color: saved ? AppColors.accentIcon : AppColors.disabled,
        ),
      );
}

/// 목록이 비었을 때.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.hint, this.icon});

  final String title;
  final String? hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 34, color: AppColors.disabled),
                const SizedBox(height: 14),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.body,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 7),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

/// 앱 곳곳에 상시로 두는 면책 고지.
///
/// 금액을 보여주는 화면에는 반드시 근거·시행일과 함께 나와야 한다.
/// 이게 이 앱의 법적 방어선이다.
class DisclaimerNote extends StatelessWidget {
  const DisclaimerNote({super.key, this.short = false});

  final bool short;

  static const _short = '이 앱의 정보는 참고용이며 법적 효력이 없습니다.';
  static const _full =
      '이 앱의 정보는 참고용이며 법적 효력이 없습니다. 실제 부과 금액과 처분은 사안에 따라 '
      '다를 수 있고, 이 앱의 정보를 신뢰해 발생한 손해에 대해 책임지지 않습니다. '
      '정확한 내용은 국가법령정보센터와 관할 기관에서 확인하세요.';

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F4EE),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1, right: 8),
              child: Icon(Icons.info_outline_rounded,
                  size: 15, color: AppColors.muted),
            ),
            Expanded(
              child: Text(
                short ? _short : _full,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.7,
                  color: AppColors.body,
                ),
              ),
            ),
          ],
        ),
      );
}
