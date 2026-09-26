// Màn chính "PCC TX Control" — màn mở app (E2): danh sách hồ sơ xe.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../controller/car_controller.dart';
import '../data/profile_repository.dart';
import '../l10n/lang.dart';
import '../models/car_profile.dart';
import '../services/car_discovery.dart';
import '../services/quick_ping.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import '../transport/ble_transport.dart';
import '../transport/transport.dart';
import '../transport/udp_transport.dart';
import '../widgets/status_badge.dart';
import 'app_settings_screen.dart';
import 'control_screen.dart';
import 'profile_wizard_screen.dart';
import 'settings_screen.dart';

class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key, required this.controller, required this.repo, required this.theme, this.pickPhoto});

  final CarController controller;
  final ProfileRepository repo;
  final ThemeController theme;

  /// Chọn ảnh, trả về đường dẫn file (null = huỷ). Mặc định mở thư viện ảnh của máy; test truyền hàm giả.
  final Future<String?> Function()? pickPhoto;

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  final Map<String, QuickPingResult> _ping = {};
  final Set<String> _pinging = {};
  String? _connectingId;

  CarController get c => widget.controller;
  ProfileRepository get repo => widget.repo;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  bool _isConnected(CarProfile p) => c.isConnected && c.connectedKey == p.connKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showMigrationReport());
  }

  /// Báo cáo một lần các hồ sơ vừa được tự chuyển sang mô hình Input → Mixer (Sprint 4 — J4)
  Future<void> _showMigrationReport() async {
    if (!mounted || repo.migrationReports.isEmpty) return;
    final reports = Map.of(repo.migrationReports);
    repo.migrationReports.clear();
    final t = context.tokens;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đã cập nhật hồ sơ xe', 'Car profiles updated')),
        content: SizedBox(
          width: 480,
          child: ListView(shrinkWrap: true, children: [
            Text(
              tr(
                  'Cấu hình điều khiển được chuyển sang dạng Input → luật mix → kênh. '
                      'Mỗi kênh cũ thành một Input "chN" và một luật; luật mix cũ được giữ nguyên thứ tự. '
                      'Bản gốc được lưu cạnh hồ sơ (đuôi .bak).',
                  'Controls now use Input → mix rule → channel. '
                      'Each old channel became an Input "chN" plus one rule; old mix rules keep their order. '
                      'The original is saved next to the profile (.bak).'),
              style: AppText.body.copyWith(color: t.textBody),
            ),
            for (final e in reports.entries) ...[
              const SizedBox(height: Gap.m),
              Text(repo.get(e.key)?.name ?? e.key, style: AppText.title.copyWith(color: t.text)),
              if (e.value.isEmpty)
                Text(tr('Không có thay đổi hành vi.', 'No behavior changes.'), style: AppText.label.copyWith(color: t.ok))
              else
                for (final w in e.value)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.xs),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AppIcon(AppIcons.warning, color: t.warn, mini: true),
                      const SizedBox(width: Gap.xs),
                      Expanded(child: Text(w, style: AppText.label.copyWith(color: t.text))),
                    ]),
                  ),
            ],
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đã hiểu', 'Got it')))],
      ),
    );
  }

  Future<void> _create() async {
    await Navigator.push<CarProfile>(
      context,
      MaterialPageRoute(builder: (_) => ProfileWizardScreen(repo: repo, controller: c)),
    );
  }

  Future<void> _edit(CarProfile p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SettingsScreen(controller: c, repo: repo, profileId: p.id)),
    );
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Future<void> _drive(CarProfile p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ControlScreen(controller: c, repo: repo, profileId: p.id)),
    );
  }

  /// Chế độ Router: IP do router cấp có thể đổi → dò xe theo mã xe, cập nhật hồ sơ nếu IP/port khác.
  /// Trả về hồ sơ (có thể đã sửa) và cờ "có thấy xe trong mạng".
  Future<(CarProfile, bool)> _locate(CarProfile p) async {
    final id = p.wifi?.carId;
    if (p.connType != ConnType.wifi || id == null) return (p, true);
    final hit = (await CarDiscovery.scan(id: id, timeout: const Duration(milliseconds: 1200)))
        .where((f) => f.id == id.toUpperCase())
        .firstOrNull;
    if (hit == null) return (p, false);
    final w = p.wifi!;
    if (hit.ip == w.ip && hit.port == w.port) return (p, true);
    final fresh = repo.get(p.id) ?? p;
    fresh.wifi!
      ..ip = hit.ip
      ..port = hit.port;
    await repo.save(fresh, touch: false);
    return (fresh, true);
  }

  Future<void> _connect(CarProfile profile) async {
    setState(() => _connectingId = profile.id);
    final (p, found) = await _locate(profile);
    if (!mounted) return;
    final CarTransport t;
    if (p.connType == ConnType.ble) {
      final mac = p.ble?.mac ?? '';
      if (mac.isEmpty) {
        setState(() => _connectingId = null);
        _snack(tr('Hồ sơ chưa có MAC. Bấm Sửa để chọn xe BLE.', 'This profile has no MAC yet. Tap Edit to pick a BLE car.'));
        return;
      }
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      t = BleTransport(BluetoothDevice.fromId(mac));
    } else {
      t = UdpTransport(p.wifi!.ip, p.wifi!.port);
    }
    await c.connect(t, key: p.connKey);
    if (!mounted) return;
    setState(() => _connectingId = null);
    if (c.error != null) {
      _snack(found
          ? c.error!
          : tr(
              '${c.error!}. Không thấy xe trong mạng: kiểm tra điện thoại và xe cùng router (không dùng mạng khách). '
                  'Xe không vào được router thì sau 15 giây tự phát WiFi riêng.',
              '${c.error!}. Car not found on the network: make sure the phone and the car use the same router '
                  '(not a guest network). If the car cannot join the router it starts its own WiFi after 15 seconds.'));
      return;
    }
    final fresh = repo.get(p.id);
    if (fresh != null) {
      fresh.lastConnectedAt = DateTime.now();
      await repo.save(fresh, touch: false);
      // Không có bước "đọc từ xe": hồ sơ trong app luôn được đưa xuống xe (E6)
      try {
        await c.syncProfile(fresh);
      } catch (e) {
        _snack(tr('Không đồng bộ được cấu hình với xe: ${e.toString().replaceFirst('Exception: ', '')}', 'Could not sync the configuration with the car: ${e.toString().replaceFirst('Exception: ', '')}'));
      }
    }
    if (mounted) await _drive(p);
  }

  Future<void> _test(CarProfile profile) async {
    setState(() {
      _pinging.add(profile.id);
      _ping.remove(profile.id);
    });
    final (p, _) = _isConnected(profile) ? (profile, true) : await _locate(profile);
    final r = await QuickPing.run(
      ble: p.connType == ConnType.ble,
      ip: p.wifi?.ip,
      port: p.wifi?.port,
      bleId: p.ble?.mac,
      controller: c,
      connectedKey: p.connKey,
    );
    if (!mounted) return;
    setState(() {
      _pinging.remove(p.id);
      _ping[p.id] = r;
    });
  }

  Future<void> _rename(CarProfile p) async {
    final ctrl = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final probe = p.copy()..name = ctrl.text;
        final err = probe.validateGeneral(otherNames: repo.namesExcept(p.id))['name'];
        return AlertDialog(
          title: Text(tr('Đổi tên xe', 'Rename car')),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 32,
            decoration: InputDecoration(errorText: err),
            onChanged: (_) => setD(() {}),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ', 'Cancel'))),
            FilledButton(
              onPressed: err == null ? () => Navigator.pop(ctx, ctrl.text.trim()) : null,
              child: Text(tr('Lưu', 'Save')),
            ),
          ],
        );
      }),
    );
    ctrl.dispose();
    if (name == null) return;
    final fresh = repo.get(p.id)!..name = name;
    await repo.save(fresh);
  }

  static Future<String?> _pickFromGallery() async {
    // Ảnh chỉ hiện nhỏ trên thẻ xe: thu nhỏ luôn khi chọn cho nhẹ file
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    return x?.path;
  }

  /// Chưa có ảnh thì mở thẳng thư viện ảnh; có rồi thì hỏi chọn ảnh khác hay bỏ ảnh
  Future<void> _photo(CarProfile p) async {
    var remove = false;
    if (p.photo != null) {
      final r = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const AppIcon(AppIcons.photo),
              title: Text(tr('Chọn ảnh khác', 'Choose another photo')),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const AppIcon(AppIcons.delete),
              title: Text(tr('Bỏ ảnh', 'Remove photo')),
              onTap: () => Navigator.pop(ctx, true),
            ),
          ]),
        ),
      );
      if (r == null) return;
      remove = r;
    }
    try {
      if (remove) {
        await repo.setPhoto(p.id, null);
        return;
      }
      final path = await (widget.pickPhoto ?? _pickFromGallery)();
      if (path != null) await repo.setPhoto(p.id, File(path));
    } catch (e) {
      _snack(tr('Không đặt được ảnh: ${e is PlatformException ? e.message ?? e.code : e}', 'Could not set the photo: ${e is PlatformException ? e.message ?? e.code : e}'));
    }
  }

  Future<void> _delete(CarProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xoá hồ sơ xe?', 'Delete car profile?')),
        content: Text('tr("${p.name}" cùng cấu hình và bố cục sẽ bị xoá khỏi máy. Cấu hình đã lưu trên xe không đổi., "${p.name}" and its settings and layout will be deleted from this phone. Settings stored on the car stay unchanged.)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xoá', 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    if (_isConnected(p)) await c.disconnect();
    await repo.delete(p.id);
  }

  Future<void> _menu(CarProfile p, String action) async {
    try {
      switch (action) {
        case 'rename':
          await _rename(p);
        case 'photo':
          await _photo(p);
        case 'duplicate':
          final d = await repo.duplicate(p.id);
          _snack(tr('Đã tạo "${d.name}"', 'Created "${d.name}"'));
        case 'export':
          final path = await repo.exportToFile(p.id);
          _snack(tr('Đã xuất: $path', 'Exported: $path'));
        case 'delete':
          await _delete(p);
      }
    } catch (e) {
      _snack(tr('Lỗi: $e', 'Error: $e'));
    }
  }

  Future<void> _openAppSettings() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AppSettingsScreen(theme: widget.theme)),
      );

  /// Nút VN / EN trên thanh tiêu đề: đổi ngôn ngữ ngay tại màn chính
  Widget _langButton(AppTokens t) {
    final lang = LangController.instance;
    return PopupMenuButton<AppLang>(
      tooltip: tr('Ngôn ngữ', 'Language'),
      initialValue: lang.lang,
      onSelected: lang.setLang,
      itemBuilder: (_) => [
        for (final l in AppLang.values)
          PopupMenuItem(
            value: l,
            child: ListTile(
              leading: SizedBox(
                width: 28,
                child: Text(l.short, style: AppText.label.copyWith(color: t.text, fontWeight: FontWeight.w700)),
              ),
              title: Text(l.nativeName),
              trailing: l == lang.lang ? AppIcon(AppIcons.check, color: t.accent, mini: true) : null,
            ),
          ),
      ],
      // Vùng chạm cao 48, viền pill 36 bên trong
      child: SizedBox(
        height: 48,
        child: Center(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: Gap.m),
            decoration: BoxDecoration(
              border: Border.all(color: t.line),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(AppIcons.language, color: t.textMuted, mini: true),
              const SizedBox(width: Gap.xs),
              Text(lang.lang.short, style: AppText.label.copyWith(color: t.text, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: Listenable.merge([repo, c, widget.theme, LangController.instance]),
      builder: (context, _) {
        final list = repo.list();
        return Scaffold(
          appBar: AppBar(
            title: const Text('PCC TX Control'),
            actions: [
              _langButton(t),
              IconButton(
                tooltip: tr('Cài đặt', 'Settings'),
                icon: const AppIcon(AppIcons.settings),
                onPressed: _openAppSettings,
              ),
              const SizedBox(width: Gap.xs),
            ],
          ),
          floatingActionButton: list.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: _create,
                  icon: const AppIcon(AppIcons.plus),
                  label: Text(tr('Tạo xe mới', 'New car')),
                ),
          body: list.isEmpty
              ? _empty(t)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(Gap.l, Gap.l, Gap.l, 96),
                  children: [
                    if (repo.loadErrors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gap.m),
                        child: Text(tr('Không đọc được ${repo.loadErrors.length} hồ sơ hỏng.', 'Could not read ${repo.loadErrors.length} damaged profile(s).'),
                            style: AppText.label.copyWith(color: t.warn)),
                      ),
                    for (final p in list) _card(p),
                  ],
                ),
        );
      },
    );
  }

  Widget _empty(AppTokens t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xxl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CustomIconView(CustomIcon.car, size: 64, color: t.textMuted),
            const SizedBox(height: Gap.l),
            Text(tr('Chưa có xe nào', 'No cars yet'), style: AppText.headline.copyWith(color: t.text)),
            const SizedBox(height: Gap.s),
            Text(tr('Tạo hồ sơ xe để lưu kết nối và cấu hình. Không cần bật xe khi tạo.', 'Create a car profile to store its connection and settings. The car does not need to be on.'),
                textAlign: TextAlign.center, style: AppText.body.copyWith(color: t.textBody)),
            const SizedBox(height: Gap.xl),
            FilledButton.icon(
              onPressed: _create,
              icon: const AppIcon(AppIcons.plus, mini: true),
              label: Text(tr('Tạo xe mới', 'New car')),
            ),
          ]),
        ),
      );

  String _lastConnected(CarProfile p) {
    final d = p.lastConnectedAt;
    if (d == null) return tr('Chưa kết nối lần nào', 'Never connected');
    String two(int n) => n.toString().padLeft(2, '0');
    return tr('Kết nối lần cuối ${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}', 'Last connected ${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}');
  }

  /// Ảnh xe (bấm để đổi); chưa có ảnh hoặc ảnh hỏng thì hiện biểu tượng xe
  Widget _avatar(CarProfile p, bool connected) {
    final t = context.tokens;
    const size = 56.0;
    final radius = BorderRadius.circular(Radii.field);
    final icon = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: connected ? t.accentContainer : t.surface2, borderRadius: radius),
      alignment: Alignment.center,
      child: CustomIconView(CustomIcon.car, color: connected ? t.onAccentContainer : t.textMuted),
    );
    final f = repo.photoFile(p);
    return Tooltip(
      message: p.photo == null ? tr('Chọn ảnh cho xe', 'Choose a car photo') : tr('Đổi ảnh xe', 'Change car photo'),
      child: InkWell(
        borderRadius: radius,
        onTap: () => _photo(p),
        child: f == null
            ? icon
            : ClipRRect(
                borderRadius: radius,
                child: Image.file(f, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => icon),
              ),
      ),
    );
  }

  Widget _card(CarProfile p) {
    final t = context.tokens;
    final connected = _isConnected(p);
    final connecting = _connectingId == p.id;
    final busy = c.state == LinkState.connecting || _connectingId != null;
    final ping = _ping[p.id];
    final pinging = _pinging.contains(p.id);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: connected ? t.accent : t.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.l, Gap.m, Gap.xs, Gap.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _avatar(p, connected),
                const SizedBox(width: Gap.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: AppText.title.copyWith(color: t.text)),
                      const SizedBox(height: 2),
                      Row(children: [
                        p.connType == ConnType.wifi
                            ? AppIcon(AppIcons.wifi, size: 16, color: t.textMuted)
                            : CustomIconView(CustomIcon.bluetooth, size: 16, color: t.textMuted),
                        const SizedBox(width: Gap.xs),
                        Flexible(
                          child: Text(p.connLabel,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label.copyWith(color: t.textMuted, fontSize: 13)),
                        ),
                      ]),
                      Text(_lastConnected(p), style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: AppIcon(AppIcons.more, color: t.textMuted),
                  onSelected: (a) => _menu(p, a),
                  itemBuilder: (_) => [
                    for (final (value, icon, label) in [
                      ('rename', AppIcons.edit, tr('Đổi tên', 'Rename')),
                      ('photo', AppIcons.photo, tr('Đổi ảnh', 'Change photo')),
                      ('duplicate', AppIcons.duplicate, tr('Nhân bản', 'Duplicate')),
                      ('export', AppIcons.exportFile, tr('Xuất', 'Export')),
                      ('delete', AppIcons.delete, tr('Xoá', 'Delete')),
                    ])
                      PopupMenuItem(value: value, child: ListTile(leading: AppIcon(icon), title: Text(label))),
                  ],
                ),
              ],
            ),
            if (connected || ping != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.s),
                child: Wrap(spacing: Gap.s, runSpacing: Gap.xs, children: [
                  if (connected) StatusBadge(state: c.state),
                  if (ping != null) Pill(color: ping.ok ? t.ok : t.bad, label: ping.label),
                ]),
              ),
            const SizedBox(height: Gap.m),
            Wrap(
              spacing: Gap.s,
              runSpacing: Gap.s,
              children: [
                if (connected) ...[
                  FilledButton.icon(
                    onPressed: () => _drive(p),
                    icon: const CustomIconView(CustomIcon.steering, size: 20),
                    label: Text(tr('Lái', 'Drive')),
                  ),
                  OutlinedButton.icon(
                    onPressed: c.disconnect,
                    icon: const AppIcon(AppIcons.disconnect, mini: true),
                    label: Text(tr('Ngắt', 'Disconnect')),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: busy ? null : () => _connect(p),
                    icon: connecting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const AppIcon(AppIcons.connect, mini: true),
                    label: Text(connecting ? tr('Đang kết nối', 'Connecting') : tr('Kết nối', 'Connect')),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _edit(p),
                  icon: const AppIcon(AppIcons.config, mini: true),
                  label: Text(tr('Sửa', 'Edit')),
                ),
                OutlinedButton.icon(
                  onPressed: pinging ? null : () => _test(p),
                  icon: pinging
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const AppIcon(AppIcons.signal, mini: true),
                  label: Text(tr('Kiểm tra', 'Test')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
