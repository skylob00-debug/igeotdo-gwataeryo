import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../widgets/common.dart';
import '../widgets/concept_card.dart';
import 'detail_page.dart';

/// 저장(즐겨찾기)한 규정.
///
/// 폐지된 것도 지우지 않고 회색으로 남긴다. 저장해 둔 항목이
/// 말없이 사라지면 안 된다.
class SavedPage extends ConsumerWidget {
  const SavedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final saved = ref.watch(savedProvider);
    final items = data.concepts.where((c) => saved.contains(c.key)).toList()
      ..sort((a, b) {
        // 폐지된 것은 아래로
        final ar = data.isConceptRepealed(a.key) ? 1 : 0;
        final br = data.isConceptRepealed(b.key) ? 1 : 0;
        if (ar != br) return ar - br;
        return b.score.compareTo(a.score);
      });

    final repealedCount =
        items.where((c) => data.isConceptRepealed(c.key)).length;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            label: '저장',
            title: '내가 저장한 규정',
            subtitle: items.isEmpty
                ? '상세 화면에서 북마크를 누르면 여기 모입니다'
                : '${items.length}건'
                    '${repealedCount > 0 ? ' · 폐지 $repealedCount건' : ''}'
                    ' · 금액이 바뀌면 알려드립니다',
          ),
        ),
        if (items.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: '저장한 규정이 없습니다',
              hint: '자주 헷갈리는 규정을 저장해 두면\n금액이 바뀔 때 알려드립니다.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverList.separated(
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == items.length) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: DisclaimerNote(short: true),
                  );
                }
                final c = items[i];
                return ConceptCard(
                  concept: c,
                  violations: data.forConcept(c.key),
                  saved: true,
                  compact: true,
                  onToggleSave: () =>
                      ref.read(savedProvider.notifier).toggle(c.key),
                  onShare: () => _share(c, data),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DetailPage(conceptKey: c.key),
                  )),
                );
              },
            ),
          ),
      ],
    );
  }

  void _share(Concept concept, AppData data) {
    final violations = data.forConcept(concept.key);
    final normal = violations.where((v) => v.zone == Zone.none);
    final pool = normal.isEmpty ? violations : normal;
    final p = headline(pool.expand((v) => v.penalties));
    SharePlus.instance.share(ShareParams(
      subject: concept.title,
      text: [
        concept.title,
        if (p != null) '${pool.first.kind.label} ${headlineNote(p)} ${won(p.amount)}',
        concept.summary,
        '',
        '— 이것도 과태료? (도로교통법 시행령 별표 기준)',
      ].join('\n'),
    ));
  }
}
