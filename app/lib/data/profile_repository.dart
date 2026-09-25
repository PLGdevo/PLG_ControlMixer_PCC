// Lưu hồ sơ xe: mỗi hồ sơ một file profiles/<id>.json trong thư mục dữ liệu app (E1).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/car_profile.dart';
import 'profile_migration.dart';

enum ImportConflict { overwrite, createNew }

class ProfileRepository extends ChangeNotifier {
  ProfileRepository(this.dir);

  final Directory dir;
  final Map<String, CarProfile> _cache = {};
  final List<String> loadErrors = [];

  /// Hồ sơ vừa được tự chuyển sang định dạng mới lúc mở app: mã hồ sơ → cảnh báo (báo cáo J4).
  /// Màn Xe của tôi hiện một lần rồi xoá.
  final Map<String, List<String>> migrationReports = {};

  static Future<ProfileRepository> open() async {
    final base = await getApplicationSupportDirectory();
    final repo = ProfileRepository(Directory('${base.path}${Platform.pathSeparator}profiles'));
    await repo.load();
    return repo;
  }

  File _file(String id) => File('${dir.path}${Platform.pathSeparator}$id.json');

  Future<void> load() async {
    _cache.clear();
    loadErrors.clear();
    if (!await dir.exists()) await dir.create(recursive: true);
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        final text = await f.readAsString();
        final raw = jsonDecode(text);
        final old = raw is Map<String, dynamic> ? raw['schemaVersion'] as int? ?? 0 : 0;
        final warnings = <String>[];
        final p = decode(text, warnings: warnings);
        _cache[p.id] = p;
        if (old < CarProfile.schemaVersion) {
          // Giữ bản gốc (không đuôi .json để không bị đọc lại), rồi ghi bản đã chuyển
          await File('${f.path.substring(0, f.path.length - 5)}.v$old.bak').writeAsString(text);
          await save(p, touch: false);
          migrationReports[p.id] = warnings;
        }
      } catch (e) {
        loadErrors.add('${f.uri.pathSegments.last}: $e');
      }
    }
    notifyListeners();
  }

  /// Sắp xếp: kết nối gần nhất lên đầu, rồi theo tên
  List<CarProfile> list() => _cache.values.toList()
    ..sort((a, b) {
      final ta = a.lastConnectedAt ?? a.updatedAt, tb = b.lastConnectedAt ?? b.updatedAt;
      final c = tb.compareTo(ta);
      return c != 0 ? c : a.name.compareTo(b.name);
    });

  /// Trả về bản sao để màn hình chỉnh nháp mà không đụng dữ liệu đã lưu
  CarProfile? get(String id) => _cache[id]?.copy();

  Iterable<String> namesExcept(String id) => _cache.values.where((p) => p.id != id).map((p) => p.name);

  Future<void> save(CarProfile p, {bool touch = true}) async {
    if (touch) p.updatedAt = DateTime.now();
    if (!await dir.exists()) await dir.create(recursive: true);
    final f = _file(p.id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(p.toJson()), flush: true);
    await tmp.rename(f.path); // ghi nguyên tử, tránh hỏng file khi tắt app giữa chừng
    _cache[p.id] = p.copy();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final f = _file(id);
    if (await f.exists()) await f.delete();
    _cache.remove(id);
    notifyListeners();
  }

  /// Nhân bản, thêm hậu tố "(bản sao)"
  Future<CarProfile> duplicate(String id) async {
    final src = _cache[id];
    if (src == null) throw StateError('Không tìm thấy hồ sơ');
    final p = src.copy()
      ..id = CarProfile.newId()
      ..name = uniqueName('${src.name} (bản sao)')
      ..lastConnectedAt = null
      ..lastSyncedAt = null
      ..lastSyncedHash = null;
    await save(p);
    return p;
  }

  String uniqueName(String base) {
    final names = _cache.values.map((p) => p.name.toLowerCase()).toSet();
    var n = base.length > 32 ? base.substring(0, 32) : base;
    var i = 2;
    while (names.contains(n.toLowerCase())) {
      final suffix = ' $i';
      n = (base.length + suffix.length > 32 ? base.substring(0, 32 - suffix.length) : base) + suffix;
      i++;
    }
    return n;
  }

  String export(String id) {
    final p = _cache[id];
    if (p == null) throw StateError('Không tìm thấy hồ sơ');
    return const JsonEncoder.withIndent('  ').convert(p.toJson());
  }

  /// Ghi file xuất vào thư mục exports/ cạnh thư mục hồ sơ; trả về đường dẫn
  Future<String> exportToFile(String id) async {
    final p = _cache[id]!;
    final out = Directory('${dir.parent.path}${Platform.pathSeparator}exports');
    if (!await out.exists()) await out.create(recursive: true);
    final safe = p.name.replaceAll(RegExp(r'[^\w\-]+', unicode: true), '_');
    final f = File('${out.path}${Platform.pathSeparator}$safe.json');
    await f.writeAsString(export(id));
    return f.path;
  }

  bool exists(String id) => _cache.containsKey(id);

  /// Nhập JSON. Trùng id mà chưa chọn cách xử lý thì ném [ImportConflictException].
  Future<CarProfile> import(String json, {ImportConflict? onConflict}) async {
    final p = decode(json);
    final errs = p.validateAll();
    if (errs.isNotEmpty) throw ProfileFormatException('Hồ sơ không hợp lệ: ${errs.first}');
    if (exists(p.id)) {
      if (onConflict == null) throw ImportConflictException(p.id);
      if (onConflict == ImportConflict.createNew) {
        p
          ..id = CarProfile.newId()
          ..name = uniqueName(p.name);
      }
    } else {
      p.name = uniqueName(p.name);
    }
    await save(p, touch: false);
    return p;
  }

  static CarProfile decode(String json, {List<String>? warnings}) {
    final raw = jsonDecode(json);
    if (raw is! Map<String, dynamic>) throw ProfileFormatException('File không phải hồ sơ xe');
    return CarProfile.fromJson(ProfileMigration.migrate(raw, warnings: warnings));
  }
}

class ImportConflictException implements Exception {
  ImportConflictException(this.id);
  final String id;
  @override
  String toString() => 'Đã có hồ sơ cùng mã $id';
}
