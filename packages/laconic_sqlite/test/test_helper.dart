import 'package:laconic/laconic.dart';

/// Shared test configuration and data setup for all database tests.
///
/// This ensures consistent test data across SQLite, MySQL, and PostgreSQL.

const String userTable = 'users';
const String postTable = 'posts';
const String commentTable = 'comments';

/// Test users data - same across all databases
final List<Map<String, Object?>> testUsers = [
  {'name': 'John', 'age': 25, 'gender': 'male'},
  {'name': 'Jane', 'age': 30, 'gender': 'female'},
  {'name': 'Jack', 'age': 35, 'gender': 'male'},
];

/// Test posts data - same across all databases
final List<Map<String, Object?>> testPosts = [
  {'user_id': 1, 'title': "John's First Thoughts", 'content': 'Content one.'},
  {'user_id': 1, 'title': "John's Second Thoughts", 'content': 'Content two.'},
  {'user_id': 2, 'title': "Jane's Insights", 'content': 'Insightful content.'},
];

/// Test comments data - same across all databases
final List<Map<String, Object?>> testComments = [
  {'post_id': 1, 'user_id': 2, 'comment_text': 'Interesting post, John!'},
  {'post_id': 1, 'user_id': 1, 'comment_text': 'Thanks Jane!'},
  {'post_id': 2, 'user_id': 1, 'comment_text': 'Great insights, Jane!'},
];

/// SQLite table creation SQL
class SqliteSchema {
  static const String createUsers = '''
    create table $userTable (
      id integer primary key autoincrement,
      name varchar(255),
      age int,
      gender varchar(255)
    )
  ''';

  static const String createPosts = '''
    create table $postTable (
      id integer primary key autoincrement,
      user_id int not null,
      title varchar(255),
      content text,
      foreign key (user_id) references $userTable(id) on delete cascade
    )
  ''';

  static const String createComments = '''
    create table $commentTable (
      id integer primary key autoincrement,
      post_id int not null,
      user_id int not null,
      comment_text text
    )
  ''';
}

/// Setup test tables and data for SQLite
Future<void> setupSqliteTestData(Laconic laconic) async {
  // Drop tables in correct order (due to foreign keys)
  await laconic.statement('drop table if exists $commentTable');
  await laconic.statement('drop table if exists $postTable');
  await laconic.statement('drop table if exists $userTable');

  // Create tables
  await laconic.statement(SqliteSchema.createUsers);
  await laconic.statement(SqliteSchema.createPosts);
  await laconic.statement(SqliteSchema.createComments);

  // Insert test data
  await laconic.table(userTable).insert(testUsers);
  await laconic.table(postTable).insert(testPosts);
  await laconic.table(commentTable).insert(testComments);
}
