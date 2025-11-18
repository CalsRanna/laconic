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
