import '../data/models.dart';

/// 금액 표기. 법령이 만원 단위로 적혀 있으니 그대로 따른다.
///
///   70000   -> '7만원'
///   150000  -> '15만원'
///   5000000 -> '500만원'
///   500     -> '500원'
String won(int amount) {
  if (amount >= 10000 && amount % 10000 == 0) return '${amount ~/ 10000}만원';
  if (amount >= 10000) {
    final man = amount ~/ 10000;
    final rest = amount % 10000;
    return '$man만${_comma(rest)}원';
  }
  return '${_comma(amount)}원';
}

/// 표 안에서 쓰는 짧은 표기. '7만'
String wonShort(int amount) =>
    amount >= 10000 && amount % 10000 == 0 ? '${amount ~/ 10000}만' : won(amount);

String _comma(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// '2026-08-01' -> '2026. 8. 1.'
String korDate(DateTime d) => '${d.year}. ${d.month}. ${d.day}.';

String? korDateStr(String? iso) {
  if (iso == null) return null;
  final d = DateTime.tryParse(iso);
  return d == null ? iso : korDate(d);
}

/// 시행일까지 남은 날. 지났으면 null.
String? dday(DateTime? date) {
  if (date == null) return null;
  final today = DateTime.now();
  final days = DateTime(date.year, date.month, date.day)
      .difference(DateTime(today.year, today.month, today.day))
      .inDays;
  if (days < 0) return null;
  return days == 0 ? '오늘' : 'D-$days';
}

/// 표 한 줄에 들어가는 금액.
///   차종이 있으면  '승합 7만 · 승용 6만 · 이륜 4만'
///   차종이 없으면  '1차 30만 · 2차 70만 · 3차 이상 100만' (생활 과태료)
///   횟수와 무관하면 '5만'
String vehicleLine(Iterable<Penalty> penalties) {
  final list = penalties.toList();
  if (list.isEmpty) return '';

  if (list.every((p) => p.vehicle == Vehicle.none)) {
    if (list.map((p) => p.amount).toSet().length == 1) {
      return wonShort(list.first.amount);
    }
    final byCount = list
      ..sort((a, b) => a.offenseCount.compareTo(b.offenseCount));
    return byCount
        .map((p) => '${p.offenseLabel} ${wonShort(p.amount)}')
        .join(' · ');
  }

  final sorted = list
    ..sort((a, b) => a.vehicle.order.compareTo(b.vehicle.order));
  return sorted
      .map((p) => '${p.vehicle.label} ${wonShort(p.amount)}')
      .join(' · ');
}

/// 카드 목록에 쓰는 대표 금액.
///
/// 차종이 있으면 승용차를 우선한다. 생활 과태료처럼 차종이 없으면 1차
/// 금액을 쓴다 — 대부분은 처음 걸리고, 2·3차를 앞세우면 겁을 주는 셈이다.
Penalty? headline(Iterable<Penalty> penalties) {
  final list = penalties.toList();
  if (list.isEmpty) return null;
  if (list.every((p) => p.vehicle == Vehicle.none)) {
    return (list..sort((a, b) => a.offenseCount.compareTo(b.offenseCount)))
        .first;
  }
  for (final want in [Vehicle.car, Vehicle.all, Vehicle.bicycle, Vehicle.pm]) {
    final hit = list.where((p) => p.vehicle == want);
    if (hit.isNotEmpty) return hit.first;
  }
  return list.first;
}

/// 대표 금액에 붙이는 설명. '승용차 기준'
///
/// 생활 과태료에서 금액이 횟수마다 같으면 붙일 말이 없다. 빈 값을 준다.
String headlineNote(Penalty p, {bool variesByCount = true}) =>
    switch (p.vehicle) {
      Vehicle.none => variesByCount ? '${p.offenseLabel} 기준' : '',
      Vehicle.all => '차종 구분 없음',
      _ => '${p.vehicle.label}차 기준',
    };
