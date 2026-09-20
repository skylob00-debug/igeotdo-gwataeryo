import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../widgets/common.dart';
import '../widgets/penalty_table.dart';

/// 개념 하나의 전체 그림.
///
/// 금액을 보여주는 화면이므로 근거 조문·출처 별표·시행일·면책이
/// 반드시 함께 나온다. 순서를 바꾸더라도 이 넷은 빠지면 안 된다.
class DetailPage extends ConsumerWidget {
  const DetailPage({super.key, required this.conceptKey});

  final String conceptKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final saved = ref.watch(savedProvider).contains(conceptKey);
    final concept =
        data.concepts.where((c) => c.key == conceptKey).firstOrNull;

    if (concept == null) {
      return const Scaffold(
        body: EmptyState(
            title: '찾을 수 없는 규정입니다', hint: '데이터가 갱신되면서 사라졌을 수 있습니다.'),
      );
    }

    final violations = data.forConcept(conceptKey);
    final repealed = data.isConceptRepealed(conceptKey);
    final sources = <Source>[
      for (final slug in {for (final v in violations) v.sourceSlug})
        ?data.source(slug),
    ];

    return Scaffold(
      appBar: AppBar(
        actions: [
          SaveButton(
            saved: saved,
            onPressed: () => ref.read(savedProvider.notifier).toggle(conceptKey),
          ),
          IconButton(
            tooltip: '공유',
            onPressed: () => _share(context, concept, violations),
            icon: const Icon(Icons.ios_share_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Row(children: [
            Pill(concept.subcategory),
            if (repealed) ...[
              const SizedBox(width: 6),
              const Pill('폐지됨',
                  color: AppColors.body, background: Color(0xFFEFEBE4)),
            ],
          ]),
          const SizedBox(height: 13),
          Text(
            concept.title,
            style: TextStyle(
              fontSize: 26,
              height: 1.3,
              letterSpacing: -0.5,
              fontWeight: FontWeight.w700,
              color: repealed ? AppColors.muted : AppColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            concept.summary,
            style: const TextStyle(
                fontSize: 14, height: 1.65, color: AppColors.body),
          ),
          if (repealed) ...[
            const SizedBox(height: 14),
            _RepealedBanner(violations: violations),
          ],
          const SizedBox(height: 18),
          PenaltyTable(violations: violations),
          for (final v in violations.where((v) => v.formula != null)) ...[
            const SizedBox(height: 12),
            _Panel(
              title: '가산 규칙',
              child: Text(
                v.formula!,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.7, color: AppColors.body),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const _KindExplainer(),
          const SizedBox(height: 12),
          _Panel(
            title: '별표 원문',
            icon: Icons.description_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final v in violations) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '${data.source(v.sourceSlug)?.label ?? ''} '
                              '${v.ref}  ',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.muted),
                        ),
                        if (v.parentAction != null)
                          TextSpan(
                            text: '${v.parentAction} / ',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        TextSpan(text: v.action),
                      ]),
                      style: const TextStyle(
                          fontSize: 12, height: 1.7, color: AppColors.body),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SourcePanel(
            violations: violations,
            sources: sources,
          ),
          const SizedBox(height: 12),
          const DisclaimerNote(),
        ],
      ),
    );
  }

  void _share(BuildContext context, Concept concept, List<Violation> violations) {
    final normal = violations.where((v) => v.zone == Zone.none);
    final p = headline((normal.isEmpty ? violations : normal)
        .expand((v) => v.penalties));
    final zone = violations.where((v) => v.zone.isProtected);
    final zp = headline(zone.expand((v) => v.penalties));

    final lines = <String>[
      concept.title,
      if (p != null)
        '${(normal.isEmpty ? violations : normal).first.kind.label} '
            '${headlineNote(p)} ${won(p.amount)}',
      if (zp != null) '보호구역 ${won(zp.amount)}',
      concept.summary,
      '',
      '— 이것도 과태료? (도로교통법 시행령 별표 기준)',
    ];
    SharePlus.instance.share(
      ShareParams(text: lines.join('\n'), subject: concept.title),
    );
  }
}

class _RepealedBanner extends StatelessWidget {
  const _RepealedBanner({required this.violations});

  final List<Violation> violations;

  @override
  Widget build(BuildContext context) {
    final at = violations
        .map((v) => v.repealedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    final why = violations
        .map((v) => v.repealedReason)
        .whereType<String>()
        .firstOrNull;

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEBE4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            at == null ? '폐지된 규정입니다' : '${korDate(at)} 폐지된 규정입니다',
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            '지금은 부과되지 않습니다. 아래 금액은 폐지 당시의 값입니다.'
            '${why == null ? '' : '\n$why'}',
            style: const TextStyle(
                fontSize: 11.5, height: 1.65, color: AppColors.body),
          ),
        ],
      ),
    );
  }
}

/// 사용자가 가장 헷갈리는 부분. 금액만 보여주면 왜 두 개인지 모른다.
class _KindExplainer extends StatelessWidget {
  const _KindExplainer();

  @override
  Widget build(BuildContext context) => _Panel(
        title: '과태료와 범칙금은 다릅니다',
        child: Text.rich(
          const TextSpan(children: [
            TextSpan(text: '무인 단속카메라에 찍히면 '),
            TextSpan(
                text: '과태료',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.ink)),
            TextSpan(text: '가 차 소유주에게 나옵니다. 경찰관에게 현장 적발되면 '),
            TextSpan(
                text: '범칙금',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.ink)),
            TextSpan(text: '과 벌점이 운전자에게 부과됩니다. 과태료가 대체로 1만원 더 비쌉니다.'),
          ]),
          style: const TextStyle(
              fontSize: 12.5, height: 1.7, color: AppColors.body),
        ),
      );
}

class _SourcePanel extends StatelessWidget {
  const _SourcePanel({
    required this.violations,
    required this.sources,
  });

  final List<Violation> violations;
  final List<Source> sources;

  @override
  Widget build(BuildContext context) {
    final bases = {for (final v in violations) v.basis}.join(' · ');
    // 법령이 갈래마다 다르다. 이 개념이 걸친 별표의 법령을 그대로 쓴다.
    final laws = {for (final s in sources) s.lawName}.join(' · ');
    final labels = sources.map((s) => s.label).join('·');
    final enforced = sources.map((s) => s.enforceDate).whereType<DateTime>();
    final amended = sources.map((s) => s.amended).whereType<String>().toSet();
    final url = sources.isEmpty ? null : sources.first.url;
    final notes = <String>{for (final s in sources) ...s.notes}.toList();

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Line(label: '근거', value: bases),
          _Line(
            // 법령 이름을 박아 두면 안 된다. 별표 번호만으로는 구분되지 않아
            // (도로교통법 별표 8 과 폐기물관리법 별표 8 이 둘 다 있다)
            // 생활 과태료에 엉뚱한 법령이 붙는다.
            label: '출처',
            value: '$laws $labels'
                '${amended.isEmpty ? '' : ' <개정 ${amended.join(', ')}>'}',
          ),
          if (enforced.isNotEmpty)
            _Line(
              label: '시행일',
              // 별표가 여럿이면 가장 늦게 시행되는 것을 쓴다.
              value: korDate(enforced.reduce((a, b) => a.isAfter(b) ? a : b)),
            ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.hairline),
            const SizedBox(height: 10),
            const Text('별표 비고',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            const SizedBox(height: 6),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(n,
                    style: const TextStyle(
                        fontSize: 11, height: 1.6, color: AppColors.muted)),
              ),
          ],
          if (url != null) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('국가법령정보센터에서 원문 보기',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.accent)),
                  SizedBox(width: 4),
                  Icon(Icons.north_east_rounded,
                      size: 13, color: AppColors.accent),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '$label  ',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.ink)),
            TextSpan(text: value),
          ]),
          style: const TextStyle(
              fontSize: 12.5, height: 1.85, color: Color(0xFF4B4F58)),
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.title, this.icon});

  final Widget child;
  final String? title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: cardDecoration(radius: AppRadius.panel),
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: AppColors.accentIcon),
                  const SizedBox(width: 7),
                ],
                Text(title!,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ]),
              const SizedBox(height: 8),
            ],
            child,
          ],
        ),
      );
}
