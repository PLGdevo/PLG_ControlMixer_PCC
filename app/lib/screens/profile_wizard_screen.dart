// Tạo xe mới: 3 bước (E3). Trả về CarProfile đã lưu qua Navigator.pop. Mẫu mặc định "Trống": chưa gán Ga/Lái vào kênh nào.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controller/car_controller.dart';
import '../data/profile_repository.dart';
import '../l10n/lang.dart';
import '../models/car_profile.dart';
import '../services/car_discovery.dart';
import '../services/quick_ping.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../transport/ble_transport.dart';
import '../widgets/status_badge.dart';

class ProfileWizardScreen extends StatefulWidget {
  const ProfileWizardScreen({super.key, required this.repo, required this.controller});

  final ProfileRepository repo;
  final CarController controller;

  @override
  State<ProfileWizardScreen> createState() => _ProfileWizardScreenState();
}

class _ProfileWizardScreenState extends State<ProfileWizardScreen> {
  int step = 0;
  late final CarProfile p = CarProfile(
    id: CarProfile.newId(),
    name: widget.repo.uniqueName(tr('Xe mới', 'New car')),
    connType: ConnType.wifi,
    wifi: WifiConn(),
    ble: BleConn(),
  );
  late final _name = TextEditingController(text: p.name);
  final _ip = TextEditingController(text: '192.168.4.1');
  final _port = TextEditingController(text: '4210');
  final _ssid = TextEditingController();
  final _mac = TextEditingController();
  final _devName = TextEditingController();

  ProfileTemplate template = ProfileTemplate.blank;
  String? copyFromId;

  QuickPingResult? pingResult;
  bool pinging = false;
  bool saving = false;

  // WiFi: xe tìm thấy trong mạng đang nối (DISCOVER)
  List<FoundCar> found = [];
  bool finding = false;

  // BLE
  List<ScanResult> results = [];
  bool scanning = false;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanningSub;

  @override
  void initState() {
    super.initState();
    try {
      _scanSub = FlutterBluePlus.scanResults.listen((r) {
        if (mounted) setState(() => results = r);
      });
      _scanningSub = FlutterBluePlus.isScanning.listen((s) {
        if (mounted) setState(() => scanning = s);
      });
    } catch (_) {
      // Nền tảng không hỗ trợ BLE (vd Windows) — vẫn nhập tay được
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanningSub?.cancel();
    FlutterBluePlus.stopScan().catchError((_) {});
    for (final t in [_name, _ip, _port, _ssid, _mac, _devName]) {
      t.dispose();
    }
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Map<String, String> get _errors => p.validateGeneral(otherNames: widget.repo.list().map((e) => e.name));

  bool get _stepValid => switch (step) {
        0 => !_errors.containsKey('name'),
        1 => p.connType == ConnType.wifi
            ? !_errors.containsKey('ip') && !_errors.containsKey('port')
            : !_errors.containsKey('ble'),
        _ => template != ProfileTemplate.copy || copyFromId != null,
      };

  Future<void> _scan() async {
    try {
      final adapter = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 3));
      if (adapter != BluetoothAdapterState.on) {
        _snack(tr('Hãy bật Bluetooth trên điện thoại', 'Turn on Bluetooth on the phone'));
        return;
      }
      setState(() => results = []);
      await FlutterBluePlus.startScan(withServices: [BleUuids.service], timeout: const Duration(seconds: 6));
    } catch (e) {
      _snack(tr('Không quét được Bluetooth trên thiết bị này', 'Bluetooth scanning is not available on this device'));
    }
  }

  void _pickBle(ScanResult r) {
    final name = r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName;
    setState(() {
      p.ble!
        ..mac = r.device.remoteId.str.toUpperCase()
        ..deviceName = name;
      _mac.text = p.ble!.mac;
      _devName.text = name;
      pingResult = null;
    });
  }

  Future<void> _find() async {
    setState(() {
      finding = true;
      found = [];
    });
    final r = await CarDiscovery.scan();
    if (!mounted) return;
    setState(() {
      finding = false;
      found = r;
    });
    if (r.isEmpty) _snack(tr('Không thấy xe nào trong mạng điện thoại đang nối', 'No car found on the network the phone is on'));
  }

  void _pickFound(FoundCar f) {
    setState(() {
      p.wifi!
        ..ip = f.ip
        ..port = f.port
        ..carId = f.id;
      _ip.text = f.ip;
      _port.text = '${f.port}';
      pingResult = null;
    });
  }

  Future<void> _test() async {
    setState(() {
      pinging = true;
      pingResult = null;
    });
    final isBle = p.connType == ConnType.ble;
    if (isBle) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
    final r = await QuickPing.run(
      ble: isBle,
      ip: p.wifi!.ip,
      port: p.wifi!.port,
      bleId: p.ble!.mac,
      controller: widget.controller,
      connectedKey: widget.controller.connectedKey,
    );
    if (!mounted) return;
    setState(() {
      pinging = false;
      pingResult = r;
    });
  }

  Future<void> _finish() async {
    if (pingResult?.ok != true) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Chưa kiểm tra được kết nối', 'Connection not verified')),
          content: Text(pingResult == null
              ? tr('Bạn chưa bấm Kiểm tra. Xe có thể đang tắt — vẫn lưu hồ sơ được và kết nối sau.', 'You have not tapped Test. The car may be off — you can still save the profile and connect later.')
              : tr('Xe không phản hồi (${pingResult!.error}). Xe có thể đang tắt — vẫn lưu hồ sơ được.', 'The car did not respond (${pingResult!.error}). It may be off — you can still save the profile.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Quay lại', 'Back'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Vẫn lưu', 'Save anyway'))),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() => saving = true);
    try {
      final src = copyFromId == null ? null : widget.repo.get(copyFromId!);
      template.applyTo(p, source: src);
      if (p.connType == ConnType.wifi) {
        p.ble = null;
      } else {
        p.wifi = null;
      }
      await widget.repo.save(p);
      if (mounted) Navigator.pop(context, p);
    } catch (e) {
      _snack(tr('Không lưu được: $e', 'Could not save: $e'));
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final titles = [
      tr('Tên và kiểu kết nối', 'Name and connection type'),
      tr('Thông tin kết nối', 'Connection details'),
      tr('Mẫu khởi đầu', 'Starting template'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Tạo xe mới', 'New car'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.l, Gap.l, Gap.l, 0),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= step ? t.accentFill : t.surface2,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                    ),
                  ),
                  if (i < 2) const SizedBox(width: Gap.s),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.l, Gap.m, Gap.l, 0),
            child: Row(children: [
              Text(tr('BƯỚC ${step + 1}/3', 'STEP ${step + 1}/3'), style: AppText.caption.copyWith(color: t.accent)),
              const SizedBox(width: Gap.s),
              Text(titles[step], style: AppText.title.copyWith(color: t.text)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Gap.l),
              children: switch (step) {
                0 => _step1(),
                1 => _step2(),
                _ => _step3(),
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
          padding: const EdgeInsets.all(Gap.m),
          child: Row(
            children: [
              if (step > 0)
                OutlinedButton.icon(
                  onPressed: saving ? null : () => setState(() => step--),
                  icon: const AppIcon(AppIcons.back, mini: true),
                  label: Text(tr('Quay lại', 'Back')),
                ),
              const Spacer(),
              FilledButton(
                onPressed: !_stepValid || saving
                    ? null
                    : step < 2
                        ? () => setState(() => step++)
                        : _finish,
                child: Text(step < 2 ? tr('Tiếp', 'Next') : tr('Tạo xe', 'Create car')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _step1() => [
        TextField(
          controller: _name,
          maxLength: 32,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('Tên xe', 'Car name'), hintText: tr('Xe tải đỏ', 'Red truck'), errorText: _errors['name']),
          onChanged: (v) => setState(() => p.name = v),
        ),
        const SizedBox(height: Gap.m),
        SegmentedButton<ConnType>(
          segments: const [
            ButtonSegment(value: ConnType.wifi, label: Text('WiFi'), icon: AppIcon(AppIcons.wifi, mini: true)),
            ButtonSegment(
                value: ConnType.ble, label: Text('Bluetooth'), icon: CustomIconView(CustomIcon.bluetooth, size: 20)),
          ],
          selected: {p.connType},
          onSelectionChanged: (s) => setState(() {
            p.connType = s.first;
            pingResult = null;
          }),
        ),
      ];

  List<Widget> _step2() {
    final t = context.tokens;
    final e = _errors;
    return [
      if (p.connType == ConnType.wifi) ...[
        Text(
            tr(
                'Nối điện thoại vào WiFi riêng của xe (mặc định "RC-CAR", mật khẩu 12345678), '
                    'hoặc vào cùng router với xe nếu xe đã được cài vào router nhà. Bấm Tìm xe để điền tự động.',
                'Connect the phone to the car WiFi (default "RC-CAR", password 12345678), '
                    'or to the same router as the car if it was set up on your home router. Tap Find car to fill in automatically.'),
            style: AppText.label.copyWith(color: t.textMuted)),
        const SizedBox(height: Gap.m),
        Row(children: [
          Expanded(child: Text(tr('Xe trong mạng', 'Cars on the network'), style: AppText.title.copyWith(color: t.text))),
          OutlinedButton.icon(
            onPressed: finding ? null : _find,
            icon: finding
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const AppIcon(AppIcons.scan, mini: true),
            label: Text(finding ? tr('Đang tìm', 'Searching') : tr('Tìm xe', 'Find car')),
          ),
        ]),
        for (final f in found)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.card),
              side: BorderSide(color: p.wifi!.carId == f.id ? t.accent : t.line),
            ),
            child: ListTile(
              onTap: () => _pickFound(f),
              leading: const AppIcon(AppIcons.wifi),
              title: Text(f.name, style: AppText.title.copyWith(fontSize: 16, color: t.text)),
              subtitle: Text('${f.ip}:${f.port} · ${f.mode.label} · ${f.id}',
                  style: AppText.label.copyWith(color: t.textMuted, fontSize: 13)),
            ),
          ),
        const SizedBox(height: Gap.m),
        TextField(
          controller: _ip,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr('Địa chỉ IP', 'IP address'), errorText: e['ip']),
          onChanged: (v) => setState(() {
            p.wifi!.ip = v.trim();
            pingResult = null;
          }),
        ),
        const SizedBox(height: Gap.m),
        TextField(
          controller: _port,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr('Port UDP', 'UDP port'), errorText: e['port']),
          onChanged: (v) => setState(() {
            p.wifi!.port = int.tryParse(v.trim()) ?? 0;
            pingResult = null;
          }),
        ),
        const SizedBox(height: Gap.m),
        TextField(
          controller: _ssid,
          decoration: InputDecoration(labelText: tr('SSID (tuỳ chọn)', 'SSID (optional)')),
          onChanged: (v) => p.wifi!.ssid = v.trim().isEmpty ? null : v.trim(),
        ),
      ] else ...[
        Row(children: [
          Expanded(child: Text(tr('Xe tìm thấy', 'Cars found'), style: AppText.title.copyWith(color: t.text))),
          OutlinedButton.icon(
            onPressed: scanning ? null : _scan,
            icon: scanning
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const AppIcon(AppIcons.scan, mini: true),
            label: Text(scanning ? tr('Đang quét', 'Scanning') : tr('Quét', 'Scan')),
          ),
        ]),
        const SizedBox(height: Gap.s),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.l),
            child: Text(tr('Chưa thấy xe nào. Bật nguồn xe rồi bấm Quét, hoặc nhập tay bên dưới.', 'No car found yet. Power on the car and tap Scan, or enter it below.'),
                textAlign: TextAlign.center, style: AppText.label.copyWith(color: t.textMuted)),
          )
        else
          for (final r in results) _bleTile(r),
        const SizedBox(height: Gap.m),
        TextField(
          controller: _mac,
          decoration: InputDecoration(labelText: 'MAC', hintText: 'AA:BB:CC:DD:EE:FF', errorText: e['ble']),
          onChanged: (v) => setState(() {
            p.ble!.mac = v.trim().toUpperCase();
            pingResult = null;
          }),
        ),
        const SizedBox(height: Gap.m),
        TextField(
          controller: _devName,
          decoration: InputDecoration(labelText: tr('Tên thiết bị BLE', 'BLE device name')),
          onChanged: (v) => setState(() => p.ble!.deviceName = v.trim()),
        ),
      ],
      const SizedBox(height: Gap.l),
      Row(children: [
        OutlinedButton.icon(
          onPressed: pinging || !_stepValid ? null : _test,
          icon: pinging
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const AppIcon(AppIcons.signal, mini: true),
          label: Text(tr('Kiểm tra', 'Test')),
        ),
        const SizedBox(width: Gap.m),
        if (pingResult != null)
          Flexible(child: Pill(color: pingResult!.ok ? t.ok : t.bad, label: pingResult!.label)),
      ]),
      if (pingResult?.ok == false)
        Padding(
          padding: const EdgeInsets.only(top: Gap.s),
          child: Text(tr('Vẫn lưu được hồ sơ khi xe đang tắt.', 'You can still save the profile while the car is off.'), style: AppText.label.copyWith(color: t.textMuted)),
        ),
    ];
  }

  Widget _bleTile(ScanResult r) {
    final t = context.tokens;
    final name = r.device.platformName.isNotEmpty
        ? r.device.platformName
        : (r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : tr('Không tên', 'Unnamed'));
    final sel = p.ble!.mac.toUpperCase() == r.device.remoteId.str.toUpperCase();
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: sel ? t.accent : t.line),
      ),
      child: ListTile(
        leading: CustomIconView(CustomIcon.car, color: sel ? t.accent : t.textMuted),
        title: Text(name),
        subtitle: Text('${r.device.remoteId}   ${r.rssi} dBm'),
        trailing: sel ? AppIcon(AppIcons.success, color: t.accent, solid: true) : null,
        onTap: () => _pickBle(r),
      ),
    );
  }

  List<Widget> _step3() {
    final others = widget.repo.list();
    return [
      RadioGroup<ProfileTemplate>(
        groupValue: template,
        onChanged: (v) => setState(() => template = v ?? template),
        child: Column(
          children: [
            for (final tpl in ProfileTemplate.values)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.card),
                  side: BorderSide(color: template == tpl ? context.tokens.accent : context.tokens.line),
                ),
                child: RadioListTile<ProfileTemplate>(
                  value: tpl,
                  enabled: tpl != ProfileTemplate.copy || others.isNotEmpty,
                  title: Text(tpl.label),
                  subtitle: Text(tpl == ProfileTemplate.copy && others.isEmpty ? tr('Chưa có xe nào để sao chép', 'No car to copy from yet') : tpl.description),
                ),
              ),
          ],
        ),
      ),
      if (template == ProfileTemplate.copy && others.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: Gap.m),
          child: DropdownButtonFormField<String>(
            initialValue: copyFromId,
            decoration: InputDecoration(labelText: tr('Sao chép từ xe', 'Copy from car')),
            items: [for (final o in others) DropdownMenuItem(value: o.id, child: Text(o.name))],
            onChanged: (v) => setState(() => copyFromId = v),
          ),
        ),
    ];
  }
}
