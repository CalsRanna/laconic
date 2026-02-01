# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Laconic is a Laravel-style SQL query builder for Dart, supporting MySQL, SQLite, and PostgreSQL databases. It provides a fluent, chainable API for building and executing database queries with 57 methods covering ~75% of Laravel Query Builder's core functionality.

The project is structured as a multi-package monorepo:
- `packages/laconic/` - Core package with QueryBuilder, Grammar interface, and shared types
- `packages/laconic_sqlite/` - SQLite driver and grammar
- `packages/laconic_mysql/` - MySQL driver and grammar
- `packages/laconic_postgresql/` - PostgreSQL driver and grammar

## Common Commands

### Testing
```bash
# Run all tests across all packages
dart test

# Run specific database tests
cd packages/laconic_sqlite && dart test
cd packages/laconic_mysql && dart test
cd packages/laconic_postgresql && dart test

# Run specific test by name
dart test --name "test_name"

# Start MySQL and PostgreSQL containers for testing
docker-compose up -d

# Stop containers
docker-compose down
```

### Code Analysis
```bash
# Run static analysis
dart analyze

# Apply automatic fixes
dart fix --apply
```

### Dependency Management
```bash
# Get dependencies
dart pub get

# Update dependencies
dart pub upgrade
```

### Run Example
```bash
dart run example/laconic_example.dart
```

## Architecture Overview

### Multi-Package Structure

```
packages/
├── laconic/                      # Core package
│   └── lib/src/
│       ├── laconic.dart          # Main entry point, Laconic class
│       ├── exception.dart        # LaconicException (preserves cause & stackTrace)
│       ├── query.dart            # LaconicQuery for logging/debugging
│       ├── result.dart           # LaconicResult wrapper
│       ├── grammar/
│       │   ├── grammar.dart      # SqlGrammar abstract base class
│       │   └── compiled_query.dart
│       └── query_builder/
│           ├── query_builder.dart # Fluent QueryBuilder
│           └── join_clause.dart   # JoinClause builder
├── laconic_sqlite/
│   └── lib/src/
│       ├── sqlite_driver.dart    # SqliteDriver implements DatabaseDriver
│       ├── sqlite_grammar.dart   # SqliteGrammar extends SqlGrammar
│       └── sqlite_config.dart
├── laconic_mysql/
│   └── lib/src/
│       ├── mysql_driver.dart     # MysqlDriver implements DatabaseDriver
│       ├── mysql_grammar.dart    # MysqlGrammar extends SqlGrammar
│       └── mysql_config.dart
└── laconic_postgresql/
    └── lib/src/
        ├── postgresql_driver.dart    # PostgresqlDriver implements DatabaseDriver
        ├── postgresql_grammar.dart   # PostgresqlGrammar extends SqlGrammar
        └── postgresql_config.dart
```

### Core Component Hierarchy

1. **Laconic (packages/laconic/lib/src/laconic.dart)** - Main entry point
   - Manages database connections via DatabaseDriver interface
   - Provides low-level execution methods: `select()`, `statement()`, `insertAndGetId()`
   - Creates QueryBuilder instances via `table()`
   - Supports transactions via `transaction()`
   - Optional query listener via `listen` parameter for logging/debugging

2. **QueryBuilder (packages/laconic/lib/src/query_builder/query_builder.dart)** - Fluent query builder
   - Uses Grammar pattern to convert method chains into SQL
   - Does NOT manipulate string concatenation directly; builds internal data structures
   - All WHERE/JOIN/ORDER clauses stored in lists, compiled lazily
   - Calls Grammar compilation methods when executing queries
   - Safety checks: `delete()`, `increment()`, `decrement()` require WHERE clause by default

3. **Grammar System (packages/*/lib/src/*_grammar.dart)** - SQL generation
   - **SqlGrammar (abstract)**: Defines SQL compilation interface in core package
   - **SqliteGrammar**: SQLite implementation (uses `?` placeholders)
   - **MysqlGrammar**: MySQL implementation (uses `?` placeholders)
   - **PostgresqlGrammar**: PostgreSQL implementation (uses `$1, $2, ...` placeholders)
   - **CompiledQuery**: Compilation result containing SQL string and bindings
   - Grammar instances are singletons per driver

4. **JoinClause (packages/laconic/lib/src/query_builder/join_clause.dart)** - JOIN condition builder
   - Separate class for complex JOIN conditions
   - Supports multiple condition types:
     - Column conditions: `on()`, `orOn()`, `whereColumn()`, `orWhereColumn()`
     - Value conditions: `where()`, `orWhere()`
     - NULL conditions: `whereNull()`, `orWhereNull()`, `whereNotNull()`, `orWhereNotNull()`
     - IN conditions: `whereIn()`, `orWhereIn()`, `whereNotIn()`, `orWhereNotIn()`
   - Mirrors Laravel's JOIN builder design

### Key Design Patterns

#### Grammar Pattern
- QueryBuilder collects query components (wheres, joins, orders, etc.)
- Grammar is responsible for compiling these components into database-specific SQL
- All SQL generation logic centralized in Grammar classes
- Each database has its own Grammar subclass in its respective package

#### Parameter Binding
- All queries use parameterized bindings to prevent SQL injection
- Grammar collects binding values during compilation
- **MySQL/SQLite**: Uses `?` placeholders with prepared statements
- **PostgreSQL**: Uses `$1, $2, ...` numbered placeholders

#### Connection Management
- **MySQL**: Uses connection pool (`MySQLConnectionPool`), lazy-loaded
- **SQLite**: Single database instance, lazy-opened
- **PostgreSQL**: Uses connection pool (`Pool`), lazy-loaded
- Connections remain open until explicit `close()` call

#### Error Handling
- Database errors wrapped in `LaconicException` which preserves `cause` and `stackTrace`
- Transaction rollback failures are caught and reported alongside the original error
- QueryBuilder methods throw `LaconicException` on invalid input
- Safety checks prevent accidental mass operations without WHERE clause

### WHERE Clause Type System

QueryBuilder supports multiple WHERE types, each stored internally as a specific map structure:

- `basic`: Basic comparison (`where('column', value)`)
- `column`: Column-to-column comparison (`whereColumn('col1', 'col2')`)
- `in`: IN clauses (`whereIn()`, `whereNotIn()`)
- `null`: NULL checks (`whereNull()`, `whereNotNull()`)
- `between`: BETWEEN clauses (`whereBetween()`, `whereNotBetween()`)
- `betweenColumns`: Column-to-column BETWEEN (`whereBetweenColumns()`)
- `all`: All columns must match (`whereAll()`)
- `any`: Any column can match (`whereAny()`)
- `none`: No columns should match (`whereNone()`)

### JOIN Types and Condition System

QueryBuilder supports multiple JOIN types:
- `join()`: INNER JOIN
- `leftJoin()`: LEFT JOIN
- `rightJoin()`: RIGHT JOIN
- `crossJoin()`: CROSS JOIN (no conditions)

JoinClause supports multiple condition types:
- `on`: Column-to-column comparison (no parameter binding)
- `column`: Column-to-column comparison via `whereColumn()` (no parameter binding)
- `where`: Column-to-value comparison (requires parameter binding)
- `null`: NULL checks via `whereNull()`, `whereNotNull()`
- `in`: IN clauses via `whereIn()`, `whereNotIn()`

## Important Code Conventions

### Adding New WHERE Types
1. Add public method in QueryBuilder (`packages/laconic/lib/src/query_builder/query_builder.dart`)
2. Add WHERE condition to `_wheres` list with appropriate type identifier
3. Add compilation logic in each Grammar's `_compileWheres()`:
   - `packages/laconic_sqlite/lib/src/sqlite_grammar.dart` (uses `?` placeholders)
   - `packages/laconic_mysql/lib/src/mysql_grammar.dart` (uses `?` placeholders)
   - `packages/laconic_postgresql/lib/src/postgresql_grammar.dart` (uses `$N` placeholders)
4. If `increment()`/`decrement()` needs support, update their `_compileWheres()` helper method
5. Add tests in all three test files

### Adding New Grammar Implementation
1. Create a new package under `packages/` (e.g., `packages/laconic_newdb/`)
2. Create Grammar class extending `SqlGrammar`
3. Implement all abstract methods: `compileSelect()`, `compileInsert()`, `compileUpdate()`, `compileDelete()`, `compileInsertGetId()`
4. Create Driver class implementing `DatabaseDriver`
5. Use singleton pattern for Grammar instance in Driver
6. Create test file following existing patterns

### Error Handling
- Database errors wrapped in `LaconicException` with preserved `cause` and `stackTrace`
- QueryBuilder methods throw `LaconicException` on invalid input
- `first()` throws on no results, `sole()` throws on no results or multiple results
- `value()` returns `null` when no results found
- `delete()`, `increment()`, `decrement()` throw without WHERE clause (use `allowWithoutWhere: true` to override)

## Testing Strategy

Tests are organized by database type:

### Test File Structure
- `packages/laconic/test/laconic_test.dart` - Core package tests
- `packages/laconic_sqlite/test/laconic_sqlite_test.dart` - SQLite tests
- `packages/laconic_mysql/test/laconic_mysql_test.dart` - MySQL tests (requires Docker)
- `packages/laconic_postgresql/test/laconic_postgresql_test.dart` - PostgreSQL tests (requires Docker)

### Running Tests
```bash
# SQLite only (no Docker required)
cd packages/laconic_sqlite && dart test

# All databases (requires Docker)
docker-compose up -d
cd packages/laconic_mysql && dart test
cd packages/laconic_postgresql && dart test
docker-compose down
```

### Test Categories
Each database test file covers:
- Basic CRUD operations
- WHERE conditions (whereIn, whereNull, whereBetween, etc.)
- Aggregate functions (count, avg, sum, max, min)
- Existence checks (exists, doesntExist)
- Pluck and value extraction
- Increment/decrement operations
- Advanced WHERE methods (whereColumn, whereAll, whereAny, whereNone)
- JOIN operations (join, leftJoin, crossJoin with various conditions)

## Dependency Requirements

Main dependencies (per package):
- `packages/laconic_mysql/`: `mysql_client` for MySQL connectivity
- `packages/laconic_sqlite/`: `sqlite3` for SQLite support
- `packages/laconic_postgresql/`: `postgres` for PostgreSQL connectivity

Dev dependencies:
- `test`: Testing framework
- Docker (for MySQL/PostgreSQL tests)
