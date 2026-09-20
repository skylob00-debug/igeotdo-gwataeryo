import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repository.dart';
import '../widgets/common.dart';
import 'detail_page.dart';

/// 제목·설명·분류에 더해 별표 원문과 근거 조문까지 뒤진다.
/// '제5조' 로도, '킥보드' 로도 찾을 수 있어야 한다.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(queryProvider));

  static const _suggestions = [
    '어린이보호구역', '전동킥보드', '안전띠', '속도위반', '고속도로', '선팅', '주차',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String q) {
    _controller.text = q;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    ref.read(queryProvider.notifier).set(q);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final query = ref.watch(queryProvider);
    final hits = Feed.search(data, query);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('검색',
                  style: TextStyle(
                      fontSize: 11.5,
                      letterSpacing: 1.1,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Container(
                height: 48,
                decoration: cardDecoration(radius: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        size: 19, color: AppColors.accentIcon),
                    const SizedBox(width: 9),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autocorrect: false,
                        textInputAction: TextInputAction.search,
                        onChanged: (v) =>
                            ref.read(queryProvider.notifier).set(v),
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.ink),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: '위반행위, 조문, 낱말',
                          hintStyle: TextStyle(
                              fontSize: 15, color: AppColors.disabled),
                        ),
                      ),
                    ),
                    if (query.isNotEmpty)
                      GestureDetector(
                        onTap: () => _setQuery(''),
                        child: Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                              color: AppColors.chipBg, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded,
                              size: 14, color: AppColors.body),
                        ),
                      ),
                  ],
                ),
              ),
              if (query.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: '위반행위 '),
                    TextSpan(
                      text: '${hits.length}건',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                    const TextSpan(text: ' · 별표 원문과 근거 조문까지 함께 찾습니다'),
                  ]),
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: query.trim().isEmpty
              ? _Suggestions(onPick: _setQuery)
              : hits.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: '찾는 규정이 없습니다',
                      hint: '낱말을 줄이거나 조문 번호로 찾아보세요. 예: 제5조',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: hits.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (context, i) =>
                          _Hit(concept: hits[i], data: data),
                    ),
        ),
      ],
    );
  }
}

class _Hit extends StatelessWidget {
  const _Hit({required this.concept, required this.data});

  final Concept concept;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final violations = data.forConcept(concept.key);
    final repealed = data.isConceptRepealed(concept.key);
    final normal = violations.where((v) => v.zone == Zone.none);
    final pool = normal.isEmpty ? violations : normal;
    final p = headline(pool.expand((v) => v.penalties));

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DetailPage(conceptKey: concept.key),
        )),
        child: Ink(
          decoration: cardDecoration(radius: 14),
          padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      concept.title,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w700,
                        color: repealed ? AppColors.muted : AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(children: [
                      Pill(concept.subcategory),
                      const SizedBox(width: 7),
                      if (repealed)
                        const Text('폐지됨',
                            style: TextStyle(
                                fontSize: 11.5, color: AppColors.muted))
                      else if (p != null)
                        Text(
                          '${pool.first.kind.label} ${won(p.amount)}',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.body),
                        ),
                    ]),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.disabled),
            ],
          ),
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onPick});

  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text('이렇게도 찾아보세요',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in _SearchPageState._suggestions)
                Material(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  child: InkWell(
                    onTap: () => onPick(s),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        border: Border.all(color: const Color(0xFFEBE4D9)),
                      ),
                      child: Text(s,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.body)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
}
