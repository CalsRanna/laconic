## 2.1.0

### Features

- **Safety Checks** - Add protection against accidental mass operations
  - `delete()` now throws `LaconicException` without WHERE clause by default
  - `increment()` now throws `LaconicException` without WHERE clause by default
  - `decrement()` now throws `LaconicException` without WHERE clause by default
  - Use `allowWithoutWhere: true` parameter to explicitly allow operations without WHERE

- **Improved `sole()` Method** - Now properly validates single record expectation
  - Throws `LaconicException` when no records found
  - Throws `LaconicException` when multiple records found (previously returned first record)

- **Enhanced Exception Handling** - `LaconicException` now preserves original error context
  - Added `cause` field to store the original exception
  - Added `stackTrace` field to preserve the original stack trace

### Improvements

- **`rawSql` Deprecation Warning** - Mark `rawSql` getter as deprecated with SQL injection warning
  - Added `@Deprecated` annotation
  - Enhanced documentation warning about security risks

### Documentation

- Update README with `sole()` method documentation
- Add safety check usage examples
- Fix `operator:` → `comparator:` parameter name in examples

## 2.0.0

### Breaking Changes

- **Driver Abstraction** - Refactor from monolithic package to workspace with driver abstraction
  - Remove hard dependencies on `mysql_client`, `sqlite3`, and `postgres`
  - Remove `Laconic.mysql()`, `Laconic.sqlite()`, `Laconic.postgresql()` factory constructors
  - Remove database-specific code from core package
  - Users now pass a `DatabaseDriver` instance to `Laconic()` constructor

- **Grammar Refactoring** - Rename `Grammar` to `SqlGrammar` and move implementations to driver packages
  - Core package only contains abstract `SqlGrammar` class
  - Each driver package provides its own grammar implementation:
    - `laconic_sqlite` → `SqliteGrammar`
    - `laconic_mysql` → `MysqlGrammar`
    - `laconic_postgresql` → `PostgresqlGrammar`

### New Features

- **`DatabaseDriver` Interface** - Abstract interface for implementing custom database drivers
  - `grammar` - Provides SQL dialect-specific `SqlGrammar` instance
  - `select()` - Execute SELECT queries
  - `statement()` - Execute non-query statements (INSERT/UPDATE/DELETE/DDL)
  - `insertAndGetId()` - Execute INSERT and return auto-increment ID
  - `transaction()` - Transaction support
  - `close()` - Close database connection

### Migration Guide

Before (1.x):
```dart
import 'package:laconic/laconic.dart';
final laconic = Laconic.mysql(MysqlConfig(...));
```

After (2.0):
```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
final laconic = Laconic(MysqlDriver(MysqlConfig(...)));
```

### Package Structure

The project is now a Dart workspace with separate driver packages:
- `laconic` - Core package with query builder and abstract interfaces
- `laconic_sqlite` - SQLite driver
- `laconic_mysql` - MySQL driver
- `laconic_postgresql` - PostgreSQL driver

## 1.0.3

### Performance

- **Fix `count()` performance issue** - Use SQL `COUNT(*)` aggregate function instead of fetching all rows
  - Before: `SELECT * FROM table` then count rows in Dart (`results.length`)
  - After: `SELECT COUNT(*) as aggregate FROM table`
  - Impact: O(n) → O(1) for network transfer and memory usage

## 1.0.2

### Features
- **Complete JOIN Support** - Add all common JOIN types aligned with Laravel
  - `leftJoin()` - LEFT JOIN queries
  - `rightJoin()` - RIGHT JOIN queries
  - `crossJoin()` - CROSS JOIN queries (cartesian product)
- **Enhanced JoinClause** - Add 12 new condition methods for complex JOIN queries
  - Column conditions: `whereColumn()`, `orWhereColumn()`
  - NULL conditions: `whereNull()`, `orWhereNull()`, `whereNotNull()`, `orWhereNotNull()`
  - IN conditions: `whereIn()`, `orWhereIn()`, `whereNotIn()`, `orWhereNotIn()`

### Testing
- Refactor test files for better organization
  - `test/test_helper.dart` - Shared configuration, schema definitions, and test data
  - `test/sqlite_test.dart` - SQLite-specific tests
  - `test/mysql_test.dart` - MySQL-specific tests
  - `test/postgresql_test.dart` - PostgreSQL-specific tests
- Unified test data across all three databases
- Total test count: 204 tests (all passing)

### Documentation
- **README restructure** - English is now the default, Chinese available as optional link
  - `README.md` - English documentation (default)
  - `README_ZH.md` - Chinese documentation
- Update COMPARISON_REPORT.md with complete JOIN coverage analysis
- Update CLAUDE.md with new architecture details and test structure
- Add comprehensive JOIN examples in documentation

### Statistics
- Total methods: 57
- Laravel coverage: ~75%
- JOIN coverage: 82%
- Test coverage: 204 test cases across 3 databases

## 1.0.1

### Features
- **PostgreSQL Support** - Add full PostgreSQL database support
  - New `Laconic.postgresql(config)` constructor
  - PostgreSQL-specific parameter binding (`$1, $2, $3...`)
  - `RETURNING id` clause for `insertGetId()`
  - Connection pooling with up to 10 concurrent connections
  - SSL connection support

### Architecture
- Add `PostgresqlGrammar` class for PostgreSQL-specific SQL generation
- Add `compileInsertGetId()` method to Grammar interface
  - Separates INSERT and INSERT RETURNING logic
  - PostgreSQL uses `RETURNING id` clause
  - MySQL/SQLite use `lastInsertId` mechanism
- Add `PostgresqlConfig` for PostgreSQL connection configuration

### Testing
- Add comprehensive PostgreSQL test suite (64 tests)
- Unify test data structure across SQLite, MySQL, and PostgreSQL
- All 187 tests passing across three databases

## 1.0.0+36

### Features
- Add advanced query methods: `whereAll()`, `whereAny()`, `whereNone()`
- Add column comparison methods: `whereBetweenColumns()`, `whereColumn()`
- Enhanced JOIN support: `orOn()`, `where()`, `orWhere()` conditions
- Add batch insert functionality, support inserting lists of data
- Add transaction support for MySQL and SQLite
- Add query listener for SQL debugging and logging
- Add `addSelect()` method for appending select fields
- Add `when()` conditional method

### Breaking Changes
- Refactor AST-based query builder to Grammar pattern
  - Simplified code structure for better maintainability
  - More flexible SQL generation mechanism
  - Easier to extend support for new databases

### Documentation
- Add Chinese documentation and improve English README
- Add comprehensive comparison report between Laconic and Laravel Query Builder
- Update CLAUDE.md with architecture details and development guide
- Enhanced example code with comprehensive usage demonstrations
- Add Flutter dependency requirement note

### Improvements
- Unify API naming: rename `mysqlLaconic` and `sqliteLaconic` to `laconic`
- Improve constructors to accept config parameters directly
- Optimize connection management with proper close calls

## 0.0.1

- Initial version.
