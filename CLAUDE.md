# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Laconic is a Laravel-style SQL query builder for Dart, supporting MySQL, SQLite, and PostgreSQL databases. It provides a fluent, chainable API for building and executing database queries with 57 methods covering ~75% of Laravel Query Builder's core functionality.

## Common Commands

### Testing
```bash
# Run all tests
dart test

# Run specific database tests
dart test test/sqlite_test.dart
dart test test/mysql_test.dart
dart test test/postgresql_test.dart

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

### Core Component Hierarchy

1. **Laconic (lib/src/laconic.dart)** - Main entry point
   - Manages database connections (MySQL connection pool / SQLite database instance)
   - Provides low-level execution methods: `select()`, `statement()`, `insertAndGetId()`
   - Creates QueryBuilder instances via `table()`
   - Supports transactions via `transaction()`
   - Optional query listener via `listen` parameter for logging/debugging

2. **QueryBuilder (lib/src/query_builder/query_builder.dart)** - Fluent query builder
   - Uses Grammar pattern to convert method chains into SQL
   - Does NOT manipulate string concatenation directly; builds internal data structures
   - All WHERE/JOIN/ORDER clauses stored in lists, compiled lazily
   - Calls Grammar compilation methods when executing queries

3. **Grammar System (lib/src/query_builder/grammar/)** - SQL generation core
   - **Grammar (abstract)**: Defines SQL compilation interface
   - **SqlGrammar**: Implementation for SQLite and MySQL (uses `?` placeholders)
   - **PostgresqlGrammar**: Implementation for PostgreSQL (uses `$1, $2, ...` placeholders)
   - **CompiledQuery**: Compilation result containing SQL string and bindings
   - Responsibility: Convert QueryBuilder's internal data structures into concrete SQL and parameter bindings

4. **JoinClause (lib/src/query_builder/join_clause.dart)** - JOIN condition builder
   - Separate class for complex JOIN conditions
   - Supports multiple condition types:
     - Column conditions: `on()`, `orOn()`, `whereColumn()`, `orWhereColumn()`
     - Value conditions: `where()`, `orWhere()`
     - NULL conditions: `whereNull()`, `orWhereNull()`, `whereNotNull()`, `orWhereNotNull()`
     - IN conditions: `whereIn()`, `orWhereIn()`, `whereNotIn()`, `orWhereNotIn()`
   - Mirrors Laravel's JOIN builder design

### Key Design Patterns

#### Grammar Pattern (Recent Refactoring)
- **Replaced**: Previous AST (abstract syntax tree) approach
- **Benefits**: Simpler, more flexible, easier to extend
- QueryBuilder collects query components (wheres, joins, orders, etc.)
- Grammar is responsible for compiling these components into database-specific SQL
- All SQL generation logic centralized in Grammar classes

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
1. Add public method in QueryBuilder
2. Add WHERE condition to `_wheres` list with appropriate type identifier
3. Add compilation logic in SqlGrammar's `_compileWheres()`
4. Add compilation logic in PostgresqlGrammar's `_compileWheres()` (uses `$N` placeholders)
5. If `increment()`/`decrement()` needs support, update their `_compileWheres()` helper method
6. Add tests in all three test files: `test/sqlite_test.dart`, `test/mysql_test.dart`, `test/postgresql_test.dart`

### Adding New Grammar Implementation
PostgreSQL is already implemented. To add another database:
1. Create new class extending `Grammar` in `lib/src/query_builder/grammar/`
2. Implement all abstract methods: `compileSelect()`, `compileInsert()`, `compileUpdate()`, `compileDelete()`
3. Override compilation helper methods if SQL syntax differs (e.g., placeholder style, quoting)
4. Add database connection class in `lib/src/laconic.dart`
5. Add factory constructor in Laconic class (e.g., `Laconic.newdb(config)`)
6. Create test file `test/newdb_test.dart` following existing patterns

### Error Handling
- Database errors wrapped in `LaconicException`
- QueryBuilder methods throw `LaconicException` on invalid input
- Example: `first()` throws on no results, `value()` returns `null`

## Testing Strategy

Tests are organized by database type with shared test data:

### Test File Structure
- `test/test_helper.dart` - Shared configuration, schema definitions, and test data
- `test/sqlite_test.dart` - SQLite tests (uses local file `laconic.db`)
- `test/mysql_test.dart` - MySQL tests (requires Docker container)
- `test/postgresql_test.dart` - PostgreSQL tests (requires Docker container)

### Test Data
All three databases use identical test data defined in `test_helper.dart`:
- 3 users (John, Jane, Jack)
- 3 posts linked to users
- 3 comments linked to posts and users

### Running Tests
```bash
# SQLite only (no Docker required)
dart test test/sqlite_test.dart

# All databases (requires Docker)
docker-compose up -d
dart test
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

**Important**: This package requires Flutter dependencies. If used in a pure Dart project, some functionality may not work properly. See README.md for details.

Main dependencies:
- `mysql_client`: MySQL connectivity
- `sqlite3`: SQLite support
- `postgres`: PostgreSQL connectivity

Dev dependencies:
- `test`: Testing framework
- Docker (for MySQL/PostgreSQL tests)
