import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';

/// 최초 실행 시 한 번만 뜨는 면책 고지.
///
/// 이 앱은 법령을 정리해 보여줄 뿐 법적 효력이 없다. 그 사실을 화면마다
/// 작게 적어 두는 것만으로는 부족하다고 보고, 시작 전에 한 번 크게 말한다.
///
/// 겁을 주자는 것이 아니다. 무엇을 믿어도 되고 무엇은 원문으로 확인해야
/// 하는지 처음에 분명히 해 두면 뒤에 오는 모든 화면이 쉬워진다.
///
/// 동의 여부는 기기에만 남는다(Repository.acceptConsent).
/// 계정이 없으므로 서버로 보내지 않는다.
class ConsentPage extends StatelessWidget {
  const ConsentPage({super.key, required this.onAccept});

  final VoidCallback onAccept;

  static const _lawUrl = 'https://www.law.go.kr';

  static const _points = [
    (
      Icons.menu_book_outlined,
      '법령 원문을 정리해 보여드립니다',
      '도로교통법 시행령 별표의 금액을 그대로 옮깁니다. 앱이 금액을 계산하거나 '
          '어림하지 않습니다.',
    ),
    (
      Icons.balance_outlined,
      '법적 효력은 없습니다',
      '실제 부과 금액과 처분은 사안, 단속 기관, 경감·가중 규정에 따라 달라집니다. '
          '이 앱의 화면은 근거가 되지 않습니다.',
    ),
    (
      Icons.shield_outlined,
      '이 정보를 믿고 한 판단에 책임지지 않습니다',
      '오류나 최신화 지연이 있을 수 있습니다. 중요한 판단은 반드시 원문과 '
          '관할 기관에서 확인하세요.',
    ),
    (
      Icons.link_rounded,
      '언제든 원문으로 갈 수 있습니다',
      '금액을 보여주는 모든 화면에 근거 조문과 시행일, 국가법령정보센터 '
          '원문 링크를 함께 둡니다.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/brand/splash_mark.png',
                        width: 64,
                        height: 64,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      '이것도 과태료?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      '시작하기 전에 네 가지만 알려드립니다',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 28),
                    for (final (icon, title, body) in _points) ...[
                      _Point(icon: icon, title: title, body: body),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(_lawUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 15),
                        label: const Text('국가법령정보센터 열기'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          textStyle: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _Footer(onAccept: onAccept),
            ],
          ),
        ),
      );
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        decoration: cardDecoration(radius: AppRadius.panel),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 17, color: AppColors.accentIcon),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.7,
                      color: AppColors.body,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onAccept});

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: onAccept,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentSolid,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('확인했습니다'),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '이 고지는 처음 한 번만 보여드립니다.',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      );
}
