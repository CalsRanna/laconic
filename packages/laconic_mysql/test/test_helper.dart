import 'package:laconic/laconic.dart';

/// MySQL table creation SQL
class MysqlSchema {
  static const String createUsers = '''
    create table ${MysqlTestData.userTable} (
      id int primary key auto_increment,
      name varchar(255),
      age int,
      gender varchar(255),
      created_at varchar(255)
    )
  ''';

  static const String createPosts = '''
    create table ${MysqlTestData.postTable} (
      id int primary key auto_increment,
      user_id int not null,
      title varchar(255),
      content text,
      foreign key (user_id) references ${MysqlTestData.userTable}(id) on delete cascade
    )
  ''';

  static const String createComments = '''
    create table ${MysqlTestData.commentTable} (
      id int primary key auto_increment,
      post_id int not null,
      user_id int not null,
      comment_text text
    )
  ''';
}

abstract final class MysqlTestData {
  /// Shared test configuration and data setup for MySQL tests.

  static const String userTable = 'users';

  static const String postTable = 'posts';

  static const String commentTable = 'comments';

  /// Test users data
  static const List<Map<String, Object?>> testUsers = [
    {
      'name': 'John',
      'age': 25,
      'gender': 'male',
      'created_at': '2024-06-15 10:30:00',
    },
    {
      'name': 'Jane',
      'age': 30,
      'gender': 'female',
      'created_at': '2024-07-20 14:00:00',
    },
    {
      'name': 'Jack',
      'age': 35,
      'gender': 'male',
      'created_at': '2023-06-15 10:30:00',
    },
  ];

  /// Test posts data
  static const List<Map<String, Object?>> testPosts = [
    {'user_id': 1, 'title': "John's First Thoughts", 'content': 'Content one.'},
    {
      'user_id': 1,
      'title': "John's Second Thoughts",
      'content': 'Content two.',
    },
    {
      'user_id': 2,
      'title': "Jane's Insights",
      'content': 'Insightful content.',
    },
  ];

  /// Test comments data
  static const List<Map<String, Object?>> testComments = [
    {'post_id': 1, 'user_id': 2, 'comment_text': 'Interesting post, John!'},
    {'post_id': 1, 'user_id': 1, 'comment_text': 'Thanks Jane!'},
    {'post_id': 2, 'user_id': 1, 'comment_text': 'Great insights, Jane!'},
  ];

  /// Setup test tables and data for MySQL
  static Future<void> setUp(Laconic laconic) async {
    // Drop tables in correct order (due to foreign keys)
    await laconic.statement('drop table if exists $commentTable');
    await laconic.statement('drop table if exists $postTable');
    await laconic.statement('drop table if exists $userTable');

    // Create tables
    await laconic.statement(MysqlSchema.createUsers);
    await laconic.statement(MysqlSchema.createPosts);
    await laconic.statement(MysqlSchema.createComments);

    // Insert test data
    await laconic.table(userTable).insert(testUsers);
    await laconic.table(postTable).insert(testPosts);
    await laconic.table(commentTable).insert(testComments);
  }
}
