import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'common.dart';

/// 홈·검색·저장 목록에 쓰는 카드.
///
/// 대표 금액 하나만 보여준다. 전체 표(일반/보호구역 x 과태료/범칙금)는
/// 상세 화면에 있다. 목록에서 네 줄을 다 보여주면 훑어보기가 어렵다.
class ConceptCard extends StatelessWidget {
  const ConceptCard({
    super.key,
    required this.concept,
    required this.violations,
    required this.saved,
    required this.onTap,
    required this.onToggleSave,
    this.compact = false,
    this.onShare,
  });

  final Concept concept;
  final List<Violation> violations;
  final bool saved;
  final VoidCallback onTap;
  final VoidCallback onToggleSave;
  final VoidCallback? onShare;

  /// 저장 목록처럼 설명을 접어야 할 때.
  final bool compact;

  bool get _repealed =>
      violations.isNotEmpty && violations.every((v) => v.isRepealed);

  /// 일반도로 금액을 대표로 삼는다. 없으면 아무거나.
  Penalty? get _headline {
    final normal = violations.where((v) => v.zone == Zone.none);
    final pool = (normal.isEmpty ? violations : normal).expand((v) => v.penalties);
    return headline(pool);
  }

  PenaltyKind? get _headlineKind {
    final normal = violations.where((v) => v.zone == Zone.none);
    final pool = normal.isEmpty ? violations : normal;
    return pool.isEmpty ? null : pool.first.kind;
  }

  @override
  Widget build(BuildContext context) {
    final p = _headline;
    final dim = _repealed;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Ink(
          decoration: cardDecoration(),
          padding: const EdgeInsets.fromLTRB(16, 13, 8, 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Pill(concept.subcategory),
                  if (dim) ...[
                    const SizedBox(width: 6),
                    const Pill('폐지됨',
                        color: AppColors.body, background: Color(0xFFEFEBE4)),
                  ],
                  const Spacer(),
                  if (onShare != null)
                    IconButton(
                      onPressed: onShare,
                      iconSize: 17,
                      visualDensity: VisualDensity.compact,
                      tooltip: '공유',
                      icon: const Icon(Icons.ios_share_rounded,
                          color: AppColors.muted),
                    ),
                  SaveButton(saved: saved, onPressed: onToggleSave, size: 18),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      concept.title,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.35,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w700,
                        color: dim ? AppColors.muted : AppColors.ink,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 6),
                      Text(
                        concept.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.55,
                          color: AppColors.body,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppColors.hairline),
                    const SizedBox(height: 11),
                    if (dim)
                      Text(
                        _repealedLine(),
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.muted),
                      )
                    else if (p != null)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _headlineKind?.label ?? '',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.muted),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            won(p.amount),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              headlineNote(p),
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.muted),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _repealedLine() {
    final at = violations
        .map((v) => v.repealedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    return at == null
        ? '지금은 부과되지 않습니다'
        : '${korDate(at)} 폐지 — 지금은 부과되지 않습니다';
  }
}
