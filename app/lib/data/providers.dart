import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'repository.dart';

/// main() 에서 load() 를 끝낸 Repository 로 갈아 끼운다.
final repositoryProvider = Provider<Repository>((ref) {
  throw UnimplementedError('main() 에서 overrideWithValue 로 넣습니다');
});

/// 현재 데이터. sync() 가 성공하면 바뀐다.
final dataProvider = NotifierProvider<DataController, AppData>(
  DataController.new,
);

class DataController extends Notifier<AppData> {
  @override
  AppData build() => ref.watch(repositoryProvider).data;

  /// 뒤에서 조용히 확인한다. 실패해도 화면은 그대로 둔다.
  Future<bool> refresh() async {
    final repo = ref.read(repositoryProvider);
    final changed = await repo.sync();
    if (changed) state = repo.data;
    return changed;
  }
}

/// 저장(즐겨찾기)한 개념 키. 기기에만 둔다.
final savedProvider = NotifierProvider<SavedController, Set<String>>(
  SavedController.new,
);

class SavedController extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.watch(repositoryProvider).saved;

  Future<void> toggle(String conceptKey) async {
    state = await ref.read(repositoryProvider).toggleSaved(conceptKey);
  }
}

/// 홈에서 고른 갈래. 'driving' 운전 / 'waste' 생활.
final homeCategoryProvider =
    NotifierProvider<CategoryController, String>(CategoryController.new);

class CategoryController extends Notifier<String> {
  @override
  String build() => 'driving';

  /// 갈래를 바꾸면 분류 필터는 푼다. 갈래마다 분류가 다르기 때문이다.
  void set(String category) {
    if (state == category) return;
    state = category;
    ref.read(homeFilterProvider.notifier).set(null);
  }
}

/// 홈 필터로 고른 분류. null 이면 전체.
final homeFilterProvider = NotifierProvider<FilterController, String?>(
  FilterController.new,
);

class FilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? subcategory) => state = subcategory;
}

/// 검색어.
final queryProvider = NotifierProvider<QueryController, String>(
  QueryController.new,
);

class QueryController extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

/// 게시된 법령 변경. 네트워크가 없으면 빈 목록.
final changesProvider = FutureProvider<List<LawChange>>((ref) async {
  return ref.watch(repositoryProvider).changes();
});
