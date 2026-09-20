import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';

/// 개념 하나의 금액을 한 표로.
///
///   일반도로   범칙금  승합 7만 · 승용 6만 · 이륜 4만 · 자전거 3만
///             과태료  승합 8만 · 승용 7만 · 이륜 5만
///   보호구역   범칙금  승합 13만 · 승용 12만 ...
///
/// 같은 위반이 별표에서 최대 네 번 나오는데, 이렇게 모아 놓으면
/// "보호구역은 2배" 가 따로 설명하지 않아도 드러난다.
class PenaltyTable extends StatelessWidget {
  const PenaltyTable({super.key, required this.violations});

  final List<Violation> violations;

  /// 일반도로를 맨 위에, 보호구역을 그 아래에.
  static const _zoneOrder = [Zone.none, Zone.both, Zone.school, Zone.senior];
  static const _kindOrder = [PenaltyKind.ticket, PenaltyKind.fine];

  @override
  Widget build(BuildContext context) {
    final byZone = <Zone, List<Violation>>{};
    for (final v in violations) {
      (byZone[v.zone] ??= []).add(v);
    }
    final zones = _zoneOrder.where(byZone.containsKey).toList();
    if (zones.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    var first = true;
    for (final zone in zones) {
      rows.add(_ZoneHeader(zone: zone, first: first));
      first = false;
      for (final kind in _kindOrder) {
        final penalties = byZone[zone]!
            .where((v) => v.kind == kind)
            .expand((v) => v.penalties)
            .toList();
        if (penalties.isEmpty) continue;
        rows.add(_Row(kind: kind, penalties: penalties, zone: zone));
      }
    }

    final all = violations.expand((v) => v.penalties).toList();
    final hasSurcharge = all.any((p) => p.surcharge != null);

    // 차종 설명은 차종이 있을 때만 값이 있다. 생활 과태료에는 차종이 없고,
    // 대신 횟수가 어떻게 세어지는지를 알려 줘야 한다.
    final byCount = all.isNotEmpty && all.every((p) => p.vehicle == Vehicle.none);
    final variesByCount =
        byCount && all.map((p) => p.amount).toSet().length > 1;

    return Container(
      decoration: cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          const Divider(height: 1, color: AppColors.hairline),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!byCount)
                  const Text(
                    '승합 = 승합차·4톤 초과 화물차·특수차·건설기계·노면전차'
                    '  /  승용 = 승용차·4톤 이하 화물차',
                    style: TextStyle(
                        fontSize: 10.5, height: 1.55, color: AppColors.muted),
                  )
                else if (variesByCount)
                  const Text(
                    '최근 1년 안에 같은 위반으로 과태료 처분을 받은 적이 있으면 '
                    '다음 차수를 적용합니다.',
                    style: TextStyle(
                        fontSize: 10.5, height: 1.55, color: AppColors.muted),
                  )
                else
                  const Text(
                    '위반 횟수와 관계없이 같은 금액입니다.',
                    style: TextStyle(
                        fontSize: 10.5, height: 1.55, color: AppColors.muted),
                  ),
                if (hasSurcharge) ...[
                  const SizedBox(height: 5),
                  const Text(
                    '괄호 안은 같은 장소에서 2시간 이상 정차·주차 위반을 하는 경우입니다.',
                    style: TextStyle(
                        fontSize: 10.5, height: 1.55, color: AppColors.zone),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneHeader extends StatelessWidget {
  const _ZoneHeader({required this.zone, required this.first});

  final Zone zone;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final protectedZone = zone.isProtected;
    return Container(
      color: protectedZone ? AppColors.zoneSoft : null,
      padding: EdgeInsets.fromLTRB(16, first ? 14 : 13, 16, 10),
      child: Row(
        children: [
          Text(
            zone.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: protectedZone ? FontWeight.w700 : FontWeight.w500,
              color: protectedZone ? AppColors.zone : AppColors.muted,
            ),
          ),
          if (zone == Zone.both) ...[
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentSolid,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: const Text('약 2배',
                  style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w500)),
            ),
            // 좁은 화면에서는 이 설명부터 줄인다. 금액이 밀리면 안 된다.
            const Spacer(),
            const Flexible(
              child: Text(
                '어린이 · 노인 · 장애인',
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: AppColors.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.kind, required this.penalties, required this.zone});

  final PenaltyKind kind;
  final List<Penalty> penalties;
  final Zone zone;

  @override
  Widget build(BuildContext context) {
    final protectedZone = zone.isProtected;

    // 차종이 없는 별표(생활 과태료)는 위반 횟수가 그 자리를 대신한다.
    // 횟수와 무관하게 금액이 같으면 칸을 하나만 그린다 — '1차 5만 · 2차 5만 ·
    // 3차 이상 5만' 은 같은 말을 세 번 하는 것이다.
    final byCount = penalties.every((p) => p.vehicle == Vehicle.none);
    final flat = byCount && penalties.map((p) => p.amount).toSet().length == 1;
    final sorted = penalties.toList()
      ..sort((a, b) => byCount
          ? a.offenseCount.compareTo(b.offenseCount)
          : a.vehicle.order.compareTo(b.vehicle.order));
    final shown = flat ? [sorted.first] : sorted;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      decoration: BoxDecoration(
        color: protectedZone ? const Color(0xFFFFFCF8) : null,
        border: const Border(
            top: BorderSide(color: AppColors.hairline, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              kind.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: protectedZone ? AppColors.zone : AppColors.ink,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var i = 0; i < shown.length; i++)
                  _Cell(
                    penalty: shown[i],
                    label: flat
                        ? ''
                        : (byCount
                            ? shown[i].offenseLabel
                            : shown[i].vehicle.label),
                    last: i == shown.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.penalty,
    required this.label,
    required this.last,
  });

  final Penalty penalty;

  /// 금액 앞에 붙는 말. 차종('승용') 또는 횟수('2차'). 없으면 빈 값.
  final String label;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final sur = penalty.surcharge;
    return Text.rich(
      TextSpan(
        children: [
          if (label.isNotEmpty) TextSpan(text: '$label '),
          TextSpan(
            text: wonShort(penalty.amount),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          if (sur != null)
            TextSpan(
              text: ' (2시간↑ ${wonShort(sur)})',
              style: const TextStyle(color: AppColors.zone, fontSize: 11.5),
            ),
          if (!last) const TextSpan(text: '  ·'),
        ],
      ),
      style: const TextStyle(
          fontSize: 12.5, height: 1.4, color: Color(0xFF4B4F58)),
    );
  }
}
