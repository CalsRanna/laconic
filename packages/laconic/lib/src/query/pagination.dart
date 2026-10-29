import '../database/result.dart';

/// A page of results with a total row count.
class LaconicPage {
  final List<LaconicResult> data;
  final int total;
  final int perPage;
  final int currentPage;
  final int lastPage;

  const LaconicPage({
    required this.data,
    required this.total,
    required this.perPage,
    required this.currentPage,
    required this.lastPage,
  });

  bool get hasMorePages => currentPage < lastPage;

  bool get isEmpty => data.isEmpty;

  bool get isNotEmpty => data.isNotEmpty;

  /// The 1-based row number of the first item, or 0 when the page is empty.
  int get from => data.isEmpty ? 0 : (currentPage - 1) * perPage + 1;

  /// The 1-based row number of the last item, or 0 when the page is empty.
  int get to => data.isEmpty ? 0 : from + data.length - 1;
}

/// A page of results without a total row count.
class LaconicSimplePage {
  final List<LaconicResult> data;
  final int perPage;
  final int currentPage;
  final bool hasMorePages;

  const LaconicSimplePage({
    required this.data,
    required this.perPage,
    required this.currentPage,
    required this.hasMorePages,
  });

  bool get isEmpty => data.isEmpty;

  bool get isNotEmpty => data.isNotEmpty;

  int get from => data.isEmpty ? 0 : (currentPage - 1) * perPage + 1;

  int get to => data.isEmpty ? 0 : from + data.length - 1;
}

/// A keyset-paginated page.
class LaconicCursorPage {
  final List<LaconicResult> data;
  final int perPage;
  final Object? nextCursor;
  final bool hasMorePages;

  const LaconicCursorPage({
    required this.data,
    required this.perPage,
    required this.nextCursor,
    required this.hasMorePages,
  });

  bool get isEmpty => data.isEmpty;

  bool get isNotEmpty => data.isNotEmpty;
}
