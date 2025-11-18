# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Laconic is a Laravel-style SQL query builder for Dart, supporting MySQL and SQLite databases. It provides a fluent, chainable API for building and executing database queries.

## Common Commands

### Testing
```bash
# Run all tests
dart test

# Run specific test file
dart test test/laconic_test.dart

# Run specific test by name
dart test --name "test_name"
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
   - **SqlGrammar**: Common implementation for SQLite and MySQL
   - **CompiledQuery**: Compilation result containing SQL string and bindings
   - Responsibility: Convert QueryBuilder's internal data structures into concrete SQL and parameter bindings

4. **JoinClause (lib/src/query_builder/join_clause.dart)** - JOIN condition builder
   - Separate class for complex JOIN conditions
   - Supports multiple condition types: `on()`, `orOn()`, `where()`, `orWhere()`
   - Mirrors Laravel's JOIN builder design

### Key Design Patterns

#### Grammar Pattern (Recent Refactoring)
- **Replaced**: Previous AST (abstract syntax tree) approach
- **Benefits**: Simpler, more flexible, easier to extend
- QueryBuilder collects query components (wheres, joins, orders, etc.)
- Grammar is responsible for compiling these components into database-specific SQL
- All SQL generation logic centralized in Grammar classes

#### Parameter Binding
- All queries use parameterized bindings (`?`) to prevent SQL injection
- Grammar collects binding values during compilation
- MySQL uses prepared statements
- SQLite uses parameterized `prepare()` and `execute()`

#### Connection Management
- **MySQL**: Uses connection pool (`MySQLConnectionPool`), lazy-loaded
- **SQLite**: Single database instance, lazy-opened
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

### JOIN Condition Types

JoinClause supports two condition types:
- `on`: Column-to-column comparison (no parameter binding)
- `where`: Column-to-value comparison (requires parameter binding)

## Important Code Conventions

### Adding New WHERE Types
1. Add public method in QueryBuilder
2. Add WHERE condition to `_wheres` list with appropriate type identifier
3. Add compilation logic in SqlGrammar's `_compileWheres()`
4. If `increment()`/`decrement()` needs support, update their `_compileWheres()` helper method
5. Add tests in `test/laconic_test.dart`

### Adding New Grammar Implementation (e.g., PostgreSQL)
1. Create new class extending `Grammar`
2. Implement all abstract methods: `compileSelect()`, `compileInsert()`, `compileUpdate()`, `compileDelete()`
3. Override compilation helper methods if SQL syntax differs
4. Select Grammar in QueryBuilder constructor based on driver

### Error Handling
- Database errors wrapped in `LaconicException`
- QueryBuilder methods throw `LaconicException` on invalid input
- Example: `first()` throws on no results, `value()` returns `null`

## Testing Strategy

Test file `test/laconic_test.dart` uses a real SQLite database:
- `setUpAll()` for each test group creates tables and inserts data
- `tearDownAll()` for each test group closes connections
- Tests cover all QueryBuilder methods and WHERE types
- Includes edge case tests (empty lists, null values, etc.)

### Running Phase-Specific Tests
Tests are organized by phases:
- Phase 1: Basic WHERE methods (whereIn, whereNull, whereBetween, etc.)
- Phase 2: Aggregate functions and helpers (avg, sum, exists, pluck, etc.)
- Phase 3: Advanced methods (addSelect, when, whereColumn, whereAll/Any/None, etc.)
- Advanced JOIN tests (orOn, where, orWhere in JOINs)

## Dependency Requirements

**Important**: This package requires Flutter dependencies. If used in a pure Dart project, some functionality may not work properly. See README.md for details.

Main dependencies:
- `mysql_client`: MySQL connectivity
- `sqlite3`: SQLite support
