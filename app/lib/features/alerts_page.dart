import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/env.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../widgets/common.dart';

/// 법령 변경 알림.
///
/// law-watch 가 매일 감지하지만, 사람이 검수해 게시(published)한 것만 내려온다.
/// 법령 API 는 자잘한 타법개정까지 잡아내므로 그대로 보여주면 잡음이 된다.
class AlertsPage extends ConsumerWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changes = ref.watch(changesProvider);

    return RefreshIndicator(
      color: AppColors.accentSolid,
      onRefresh: () async => ref.invalidate(changesProvider),
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: PageHeader(
              label: '알림',
              title: '바뀌는 법',
              subtitle: '법제처 국가법령정보를 매일 확인합니다',
            ),
          ),
          switch (changes) {
            AsyncData(value: final list) when list.isEmpty =>
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: Env.hasBackend ? '아직 알려드릴 변경이 없습니다' : '알림은 연결 후에 받습니다',
                  hint: Env.hasBackend
                      ? '도로교통법이 개정되거나 금액이 바뀌면\n검수를 거쳐 여기에 올립니다.'
                      : '지금은 앱에 담긴 자료만 보고 있습니다.',
                ),
              ),
            AsyncData(value: final list) => SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList.separated(
                  itemCount: list.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => i == list.length
                      ? const _Footer()
                      : _ChangeCard(change: list[i]),
                ),
              ),
            AsyncError() => const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: '알림을 불러오지 못했습니다',
                  hint: '연결을 확인하고 아래로 당겨 새로고침하세요.',
                ),
              ),
            _ => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          },
        ],
      ),
    );
  }
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});

  final LawChange change;

  (Color, Color) get _tagColors => switch (change.changeType) {
        'byeolpyo_changed' => (Colors.white, AppColors.accentSolid),
        'amended' => (AppColors.body, const Color(0xFFEFEBE4)),
        _ => (AppColors.zone, AppColors.accentSoft),
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _tagColors;
    final d = dday(change.enforceDate);

    return Container(
      decoration: cardDecoration(radius: AppRadius.panel),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Pill(change.typeLabel, color: fg, background: bg),
            const Spacer(),
            if (d != null)
              Text(d,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.muted)),
          ]),
          const SizedBox(height: 9),
          Text(
            change.title,
            style: const TextStyle(
                fontSize: 16,
                height: 1.4,
                letterSpacing: -0.2,
                fontWeight: FontWeight.w700),
          ),
          if (change.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(change.body,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.6, color: AppColors.body)),
          ],
          const SizedBox(height: 11),
          const Divider(height: 1, color: AppColors.hairline),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.event_outlined,
                size: 14, color: AppColors.accentIcon),
            const SizedBox(width: 6),
            Text(
              change.enforceDate == null
                  ? '시행일 미정'
                  : '${korDate(change.enforceDate!)} 시행',
              style: const TextStyle(fontSize: 11.5, color: AppColors.body),
            ),
            const Spacer(),
            if (change.sourceUrl != null)
              InkWell(
                onTap: () => launchUrl(Uri.parse(change.sourceUrl!),
                    mode: LaunchMode.externalApplication),
                child: const Text('원문',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.accent)),
              ),
          ]),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F4EE),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('금액이 바뀌면 먼저 알려드립니다',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            SizedBox(height: 6),
            Text(
              '별표(금액표)가 개정되면 감지해 검수한 뒤 반영합니다. '
              '검수 전 수치는 앱에 올리지 않습니다.',
              style: TextStyle(
                  fontSize: 11, height: 1.7, color: AppColors.body),
            ),
          ],
        ),
      );
}
