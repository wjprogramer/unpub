import 'package:mongo_dart/mongo_dart.dart';
import 'package:intl/intl.dart';
import 'package:unpub/src/models.dart';

final packageCollection = 'packages';
final statsCollection = 'stats';

class MetaStore {
  Db db;

  MetaStore(String uri) : db = Db(uri);

  Future<UnpubPackage> queryPackage(String package) async {
    var json = await db
        .collection(packageCollection)
        .findOne(where.eq('name', package));
    if (json == null) return null;
    return UnpubPackage.fromJson(json);
  }

  Future<UnpubVersion> queryPackageVersion(String name, String version) async {
    var package = await queryPackage(name);
    if (package == null) return null;

    return package.versions
        .firstWhere((item) => item.version == version, orElse: () => null);
  }

  Future<void> addVersion(String name, UnpubVersion version) async {
    await Future.wait([
      db.collection(packageCollection).update(
          where.eq('name', name),
          {
            '\$push': {
              'versions': version.toJson(),
            },
            '\$addToSet': {
              'uploaders': version.uploader,
            }
          },
          upsert: true),
      db.collection(statsCollection).update(
          where.eq('name', name),
          {
            '\$setOnInsert': {'download': 0}
          },
          upsert: true)
    ]);
  }

  Future<void> addUploader(String name, String email) async {
    await db.collection(packageCollection).update(
        where.eq('name', name),
        {
          '\$push': {
            'uploaders': email,
          }
        },
        upsert: true);
  }

  Future<void> removeUploader(String name, String email) async {
    await db.collection(packageCollection).update(
        where.eq('name', name),
        {
          '\$pull': {
            'uploaders': email,
          }
        },
        upsert: true);
  }

  void increaseDownloadCount(String name) {
    var today = DateFormat('yyyyMMdd').format(DateTime.now());
    db.collection(statsCollection).update(
        where.eq('name', name),
        {
          '\$inc': {'download': 1, 'd$today': 1}
        },
        upsert: true);
  }

  Future<int> queryCount(String q) async {
    var selector = q == null ? null : where.match('name', '.*$q.*');
    var count = await db.collection(statsCollection).count(selector);
    return count;
  }

  Future<List<UnpubPackage>> querySortedPackages(
      int size, int page, String sort, String q) async {
    var selector =
        where.sortBy(sort, descending: true).limit(size).skip(page * size);
    if (q != null) {
      selector = selector.match('name', '.*$q.*');
    }

    var packageNames = await db
        .collection(statsCollection)
        .find(selector)
        .map((item) => item['name'] as String)
        .toList();

    var packages =
        await Future.wait(packageNames.map((name) => queryPackage(name)));
    return packages;
  }
}
