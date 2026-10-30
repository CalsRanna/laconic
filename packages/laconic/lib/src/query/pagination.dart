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

/// A keyset boundary and the direction in which to fetch the next page.
///
/// [parameters] maps each ORDER BY column to its non-null boundary value.
/// Reuse the same query ordering when passing this cursor to another request.
class LaconicCursor {
  /// The values of all ordering columns at the page boundary.
  final Map<String, Object?> parameters;

  /// Whether to fetch items after the boundary in the query's ordering.
  final bool pointsToNextItems;

  /// Creates a cursor with an immutable snapshot of [parameters].
  LaconicCursor(
    Map<String, Object?> parameters, {
    this.pointsToNextItems = true,
  }) : parameters = Map.unmodifiable(parameters);
}

/// A keyset-paginated page in the query's original ordering.
class LaconicCursorPage {
  final List<LaconicResult> data;
  final int perPage;
  final LaconicCursor? nextCursor;
  final LaconicCursor? previousCursor;

  /// Whether another page follows this page in the query's ordering.
  final bool hasMorePages;

  const LaconicCursorPage({
    required this.data,
    required this.perPage,
    required this.nextCursor,
    required this.hasMorePages,
    this.previousCursor,
  });

  /// Whether another page precedes this page in the query's ordering.
  bool get hasPreviousPages => previousCursor != null;

  bool get isEmpty => data.isEmpty;

  bool get isNotEmpty => data.isNotEmpty;
}
