import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/providers.dart';
import '../data/repository.dart';
import '../widgets/common.dart';
import '../widgets/concept_card.dart';
import 'detail_page.dart';

/// 몰랐을 가능성이 높은 것부터 보여준다.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final saved = ref.watch(savedProvider);
    final filter = ref.watch(homeFilterProvider);
    final category = ref.watch(homeCategoryProvider);
    final items = Feed.home(data, category: category, subcategory: filter);
    final subs = Feed.subcategories(data, category: category);
    final source = data.sources
        .where((s) => s.slug.startsWith(category == 'driving' ? 'byeolpyo' : 'waste'))
        .firstOrNull;

    return RefreshIndicator(
      color: AppColors.accentSolid,
      onRefresh: () async {
        final changed = await ref.read(dataProvider.notifier).refresh();
        if (context.mounted && changed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('새 자료를 받았습니다')),
          );
        }
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              label: '이것도 과태료?',
              title: '몰랐다가 무는 과태료',
              // 법령이 갈래마다 다르다. 고른 갈래의 출처를 보여준다.
              subtitle: '${source?.lawName ?? data.lawName} 별표 기준'
                  '${source?.enforceDate == null ? '' : ' · ${korDate(source!.enforceDate!)} 시행'}',
              trailing: IconButton(
                tooltip: '정보',
                onPressed: () => _showAbout(context, ref),
                icon: const Icon(Icons.info_outline_rounded,
                    size: 20, color: AppColors.muted),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
              child: _CategoryTabs(
                value: category,
                onChanged: ref.read(homeCategoryProvider.notifier).set,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: subs.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final label = i == 0 ? '전체' : subs[i - 1];
                  final selected = i == 0 ? filter == null : filter == subs[i - 1];
                  return _Chip(
                    label: label,
                    selected: selected,
                    onTap: () => ref.read(homeFilterProvider.notifier)
                        .set(i == 0 ? null : subs[i - 1]),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
          if (items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(title: '해당하는 규정이 없습니다'),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 11),
                itemBuilder: (context, i) {
                  final c = items[i];
                  return ConceptCard(
                    concept: c,
                    violations: data.forConcept(c.key),
                    saved: saved.contains(c.key),
                    onToggleSave: () =>
                        ref.read(savedProvider.notifier).toggle(c.key),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DetailPage(conceptKey: c.key),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context, WidgetRef ref) {
    final data = ref.read(dataProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('이것도 과태료?',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(
                '${data.lawName}의 과태료·범칙금 별표를 그대로 옮겨 담았습니다.\n'
                '금액은 사람이 검수한 값만 싣습니다.',
                style: const TextStyle(
                    fontSize: 12.5, height: 1.7, color: AppColors.body),
              ),
              const SizedBox(height: 14),
              for (final s in data.sources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${s.label}  ${s.title}'
                    '${s.amended == null ? '' : '  <개정 ${s.amended}>'}',
                    style: const TextStyle(
                        fontSize: 11, height: 1.6, color: AppColors.muted),
                  ),
                ),
              const SizedBox(height: 16),
              const DisclaimerNote(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 운전 / 생활 갈래 전환.
///
/// 분류 칩(주정차·속도…)과 생김새를 달리했다. 둘 다 칩이면 무엇이 큰 축인지
/// 알 수 없다. 이쪽은 두 칸을 꽉 채운 세그먼트로 두어 위계를 보인다.
class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _tabs = [
    ('driving', Icons.directions_car_filled_outlined, '운전'),
    ('waste', Icons.delete_outline_rounded, '생활'),
  ];

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.chipBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final (code, icon, label) in _tabs)
              Expanded(
                child: Semantics(
                  selected: value == code,
                  button: true,
                  child: Material(
                    color: value == code ? AppColors.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    elevation: value == code ? 1 : 0,
                    shadowColor: const Color(0x1422242A),
                    child: InkWell(
                      onTap: () => onChanged(code),
                      borderRadius: BorderRadius.circular(9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon,
                              size: 15,
                              color: value == code
                                  ? AppColors.accentIcon
                                  : AppColors.muted),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: value == code
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: value == code
                                  ? AppColors.ink
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}


class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.accentSolid : AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: selected
                  ? null
                  : Border.all(color: const Color(0xFFEBE4D9)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected ? Colors.white : AppColors.body,
              ),
            ),
          ),
        ),
      );
}
