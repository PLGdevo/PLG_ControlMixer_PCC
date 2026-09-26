// Lưu hồ sơ xe: mỗi hồ sơ một file profiles/<id>.json trong thư mục dữ liệu app (E1).
// Ảnh đại diện xe nằm ở profiles/photos/, hồ sơ chỉ giữ tên file.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/lang.dart';
import '../models/car_profile.dart';
import 'profile_migration.dart';

enum ImportConflict { overwrite, createNew }

class ProfileRepository extends ChangeNotifier {
  ProfileRepository(this.dir);

  final Directory dir;
  final Map<String, CarProfile> _cache = {};
  final List<String> loadErrors = [];

  /// Hồ sơ vừa được tự chuyển sang định dạng mới lúc mở app: mã hồ sơ → cảnh báo (báo cáo J4).
  /// Màn chính hiện một lần rồi xoá.
  final Map<String, List<String>> migrationReports = {};

  static Future<ProfileRepository> open() async {
    final base = await getApplicationSupportDirectory();
    final repo = ProfileRepository(Directory('${base.path}${Platform.pathSeparator}profiles'));
    await repo.load();
    return repo;
  }

  File _file(String id) => File('${dir.path}${Platform.pathSeparator}$id.json');

  /// Thư mục con: load() chỉ đọc file .json ngay trong [dir] nên không đụng tới
  Directory get photoDir => Directory('${dir.path}${Platform.pathSeparator}photos');

  /// File ảnh đại diện của hồ sơ; null nếu không có ảnh
  File? photoFile(CarProfile p) => _photoAt(p.photo);

  /// Chỉ nhận tên file trần (hồ sơ nhập từ ngoài có thể ghi bậy) để không đọc / xoá ra ngoài thư mục ảnh
  File? _photoAt(String? name) => name == null || !RegExp(r'^[\w-]+\.\w+$').hasMatch(name)
      ? null
      : File('${photoDir.path}${Platform.pathSeparator}$name');

  /// Đặt ảnh đại diện: chép [source] vào thư mục ảnh (tên mới mỗi lần để ảnh cũ không còn trong cache),
  /// [source] null = bỏ ảnh. Ảnh cũ bị xoá khi không còn hồ sơ nào dùng (bản nhân bản dùng chung ảnh).
  Future<void> setPhoto(String id, File? source) async {
    final p = _cache[id]?.copy();
    if (p == null) throw StateError(tr('Không tìm thấy hồ sơ', 'Profile not found'));
    final old = p.photo;
    p.photo = null;
    if (source != null) {
      if (!await photoDir.exists()) await photoDir.create(recursive: true);
      final ext = RegExp(r'\.(\w{1,5})$').firstMatch(source.path)?.group(1)?.toLowerCase() ?? 'jpg';
      final name = '${id.replaceAll(RegExp(r'[^\w-]'), '_')}-${DateTime.now().millisecondsSinceEpoch}.$ext';
      await source.copy(_photoAt(name)!.path);
      p.photo = name;
    }
    await save(p);
    await _dropPhoto(old);
  }

  Future<void> _dropPhoto(String? name) async {
    final f = _photoAt(name);
    if (f == null || _cache.values.any((p) => p.photo == name)) return;
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

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

  /// Lần ghi đang chờ của từng hồ sơ: các lần lưu sát nhau (trim nhấn giữ, thoát màn Lái) ghi lần lượt,
  /// không tranh nhau file .tmp
  final Map<String, Future<void>> _writes = {};

  Future<void> _queue(String id, Future<void> Function() job) {
    final next = (_writes[id] ?? Future<void>.value()).catchError((Object _) {}).then((_) => job());
    _writes[id] = next;
    return next;
  }

  Future<void> save(CarProfile p, {bool touch = true}) {
    if (touch) p.updatedAt = DateTime.now();
    final snap = p.copy(); // nội dung tại lúc gọi, dù phải chờ lần ghi trước
    return _queue(p.id, () async {
      if (!await dir.exists()) await dir.create(recursive: true);
      final f = _file(snap.id);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(snap.toJson()), flush: true);
      await tmp.rename(f.path); // ghi nguyên tử, tránh hỏng file khi tắt app giữa chừng
      _cache[snap.id] = snap;
      notifyListeners();
    });
  }

  Future<void> delete(String id) async {
    await (_writes[id] ?? Future<void>.value()).catchError((Object _) {}); // lần ghi đang chờ không được hồi sinh file đã xoá
    final f = _file(id);
    if (await f.exists()) await f.delete();
    await _dropPhoto(_cache.remove(id)?.photo);
    notifyListeners();
  }

  /// Nhân bản, thêm hậu tố "(bản sao)"
  Future<CarProfile> duplicate(String id) async {
    final src = _cache[id];
    if (src == null) throw StateError(tr('Không tìm thấy hồ sơ', 'Profile not found'));
    final p = src.copy()
      ..id = CarProfile.newId()
      ..name = uniqueName(tr('${src.name} (bản sao)', '${src.name} (copy)'))
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
    if (p == null) throw StateError(tr('Không tìm thấy hồ sơ', 'Profile not found'));
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
    if (errs.isNotEmpty) throw ProfileFormatException(tr('Hồ sơ không hợp lệ: ${errs.first}', 'Invalid profile: ${errs.first}'));
    // File xuất không kèm ảnh: chỉ giữ tên ảnh nếu ảnh đó có sẵn trên máy này
    final photo = _photoAt(p.photo);
    if (photo == null || !await photo.exists()) p.photo = null;
    final replaced = _cache[p.id]?.photo;
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
    await _dropPhoto(replaced);
    return p;
  }

  static CarProfile decode(String json, {List<String>? warnings}) {
    final raw = jsonDecode(json);
    if (raw is! Map<String, dynamic>) throw ProfileFormatException(tr('File không phải hồ sơ xe', 'File is not a car profile'));
    return CarProfile.fromJson(ProfileMigration.migrate(raw, warnings: warnings));
  }
}

class ImportConflictException implements Exception {
  ImportConflictException(this.id);
  final String id;
  @override
  String toString() => tr('Đã có hồ sơ cùng mã $id', 'A profile with ID $id already exists');
}
