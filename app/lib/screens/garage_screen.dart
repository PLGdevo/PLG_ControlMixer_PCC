// "Xe của tôi" — màn mở app (E2): danh sách hồ sơ xe.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controller/car_controller.dart';
import '../data/profile_repository.dart';
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
import 'control_screen.dart';
import 'profile_wizard_screen.dart';
import 'settings_screen.dart';

class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key, required this.controller, required this.repo, required this.theme});

  final CarController controller;
  final ProfileRepository repo;
  final ThemeController theme;

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
        title: const Text('Đã cập nhật hồ sơ xe'),
        content: SizedBox(
          width: 480,
          child: ListView(shrinkWrap: true, children: [
            Text(
              'Cấu hình điều khiển được chuyển sang dạng Input → luật mix → kênh. '
              'Mỗi kênh cũ thành một Input "chN" và một luật; luật mix cũ được giữ nguyên thứ tự. '
              'Bản gốc được lưu cạnh hồ sơ (đuôi .bak).',
              style: AppText.body.copyWith(color: t.textBody),
            ),
            for (final e in reports.entries) ...[
              const SizedBox(height: Gap.m),
              Text(repo.get(e.key)?.name ?? e.key, style: AppText.title.copyWith(color: t.text)),
              if (e.value.isEmpty)
                Text('Không có thay đổi hành vi.', style: AppText.label.copyWith(color: t.ok))
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
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu'))],
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
        _snack('Hồ sơ chưa có MAC. Bấm Sửa để chọn xe BLE.');
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
          : '${c.error!}. Không thấy xe trong mạng: kiểm tra điện thoại và xe cùng router (không dùng mạng khách). '
              'Xe không vào được router thì sau 15 giây tự phát WiFi riêng.');
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
        _snack('Không đồng bộ được cấu hình với xe: ${e.toString().replaceFirst('Exception: ', '')}');
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
          title: const Text('Đổi tên xe'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 32,
            decoration: InputDecoration(errorText: err),
            onChanged: (_) => setD(() {}),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
            FilledButton(
              onPressed: err == null ? () => Navigator.pop(ctx, ctrl.text.trim()) : null,
              child: const Text('Lưu'),
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

  Future<void> _delete(CarProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá hồ sơ xe?'),
        content: Text('"${p.name}" cùng cấu hình và bố cục sẽ bị xoá khỏi máy. Cấu hình đã lưu trên xe không đổi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xoá')),
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
        case 'duplicate':
          final d = await repo.duplicate(p.id);
          _snack('Đã tạo "${d.name}"');
        case 'export':
          final path = await repo.exportToFile(p.id);
          _snack('Đã xuất: $path');
        case 'delete':
          await _delete(p);
      }
    } catch (e) {
      _snack('Lỗi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: Listenable.merge([repo, c, widget.theme]),
      builder: (context, _) {
        final list = repo.list();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Xe của tôi'),
            actions: [
              PopupMenuButton<ThemeMode>(
                tooltip: 'Giao diện',
                icon: AppIcon(switch (widget.theme.mode) {
                  ThemeMode.light => AppIcons.themeLight,
                  ThemeMode.dark => AppIcons.themeDark,
                  ThemeMode.system => AppIcons.themeSystem,
                }),
                initialValue: widget.theme.mode,
                onSelected: widget.theme.setMode,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: ThemeMode.dark, child: ListTile(leading: AppIcon(AppIcons.themeDark), title: Text('Tối'))),
                  PopupMenuItem(
                      value: ThemeMode.light,
                      child: ListTile(leading: AppIcon(AppIcons.themeLight), title: Text('Sáng'))),
                  PopupMenuItem(
                      value: ThemeMode.system,
                      child: ListTile(leading: AppIcon(AppIcons.themeSystem), title: Text('Theo hệ thống'))),
                ],
              ),
              const SizedBox(width: Gap.xs),
            ],
          ),
          floatingActionButton: list.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: _create,
                  icon: const AppIcon(AppIcons.plus),
                  label: const Text('Tạo xe mới'),
                ),
          body: list.isEmpty
              ? _empty(t)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(Gap.l, Gap.l, Gap.l, 96),
                  children: [
                    if (repo.loadErrors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gap.m),
                        child: Text('Không đọc được ${repo.loadErrors.length} hồ sơ hỏng.',
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
            Text('Chưa có xe nào', style: AppText.headline.copyWith(color: t.text)),
            const SizedBox(height: Gap.s),
            Text('Tạo hồ sơ xe để lưu kết nối và cấu hình. Không cần bật xe khi tạo.',
                textAlign: TextAlign.center, style: AppText.body.copyWith(color: t.textBody)),
            const SizedBox(height: Gap.xl),
            FilledButton.icon(
              onPressed: _create,
              icon: const AppIcon(AppIcons.plus, mini: true),
              label: const Text('Tạo xe mới'),
            ),
          ]),
        ),
      );

  String _lastConnected(CarProfile p) {
    final d = p.lastConnectedAt;
    if (d == null) return 'Chưa kết nối lần nào';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Kết nối lần cuối ${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
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
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: connected ? t.accentContainer : t.surface2,
                    borderRadius: BorderRadius.circular(Radii.field),
                  ),
                  alignment: Alignment.center,
                  child: CustomIconView(CustomIcon.car, color: connected ? t.onAccentContainer : t.textMuted),
                ),
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
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: ListTile(leading: AppIcon(AppIcons.edit), title: Text('Đổi tên'))),
                    PopupMenuItem(
                        value: 'duplicate', child: ListTile(leading: AppIcon(AppIcons.duplicate), title: Text('Nhân bản'))),
                    PopupMenuItem(value: 'export', child: ListTile(leading: AppIcon(AppIcons.exportFile), title: Text('Xuất'))),
                    PopupMenuItem(value: 'delete', child: ListTile(leading: AppIcon(AppIcons.delete), title: Text('Xoá'))),
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
                    label: const Text('Lái'),
                  ),
                  OutlinedButton.icon(
                    onPressed: c.disconnect,
                    icon: const AppIcon(AppIcons.disconnect, mini: true),
                    label: const Text('Ngắt'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: busy ? null : () => _connect(p),
                    icon: connecting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const AppIcon(AppIcons.connect, mini: true),
                    label: Text(connecting ? 'Đang kết nối' : 'Kết nối'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _edit(p),
                  icon: const AppIcon(AppIcons.config, mini: true),
                  label: const Text('Sửa'),
                ),
                OutlinedButton.icon(
                  onPressed: pinging ? null : () => _test(p),
                  icon: pinging
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const AppIcon(AppIcons.signal, mini: true),
                  label: const Text('Kiểm tra'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
