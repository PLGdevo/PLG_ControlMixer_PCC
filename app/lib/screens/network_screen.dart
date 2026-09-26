// Màn "Mạng của xe": đọc và đổi cấu hình mạng lưu trên xe — chế độ khi bật nguồn (AP / Router),
// WiFi riêng của xe, WiFi router (IP động/tĩnh), port UDP, tên thiết bị; vào chế độ cấu hình (WiFi tạm).
// Cấu hình mạng nằm trên xe vì xe cần nó lúc khởi động, nên chỉ đọc/sửa được khi đang nối xe.
// Đặc tả: dac_ta_wifi_3_che_do.md
import 'dart:convert';

import 'package:flutter/material.dart';

import '../controller/car_controller.dart';
import '../data/profile_repository.dart';
import '../models/car_profile.dart';
import '../protocol/net_protocol.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/status_badge.dart';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key, required this.controller, required this.repo, required this.profileId});

  final CarController controller;
  final ProfileRepository repo;
  final String profileId;

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  NetStatus? status;
  NetConfig? saved; // như đọc từ xe
  NetConfig? cfg; // bản đang sửa
  String? loadError;
  bool busy = false;
  bool showApPass = false, showStaPass = false;
  late final String _key;

  final _name = TextEditingController();
  final _port = TextEditingController();
  final _apSsid = TextEditingController();
  final _apPass = TextEditingController();
  final _apIp = TextEditingController();
  final _staSsid = TextEditingController();
  final _staPass = TextEditingController();
  final _staIp = TextEditingController();
  final _staGateway = TextEditingController();
  final _staSubnet = TextEditingController();
  final _staDns = TextEditingController();

  List<TextEditingController> get _fields =>
      [_name, _port, _apSsid, _apPass, _apIp, _staSsid, _staPass, _staIp, _staGateway, _staSubnet, _staDns];

  CarController get c => widget.controller;

  /// Đang nối đúng xe của hồ sơ này
  bool get _connected => c.isConnected && c.connectedKey == _key;

  bool get _dirty => cfg != null && saved != null && cfg!.signature != saved!.signature;

  @override
  void initState() {
    super.initState();
    _key = widget.repo.get(widget.profileId)?.connKey ?? '';
    if (_connected) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final t in _fields) {
      t.dispose();
    }
    super.dispose();
  }

  static String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------- Đọc ----------------
  Future<void> _load() async {
    setState(() {
      busy = true;
      loadError = null;
    });
    NetStatus? st;
    try {
      st = await c.readNetStatus();
      final cf = await c.readNetConfig();
      if (!mounted) return;
      setState(() {
        status = st;
        saved = cf;
        cfg = cf.copy();
        showApPass = showStaPass = false;
        _fill(cf);
      });
    } catch (e) {
      if (mounted) setState(() => loadError = _msg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    final id = st?.id;
    if (id != null) await _patchProfile((w, p) => w.carId = id); // để app tự dò xe khi IP đổi
  }

  void _fill(NetConfig cf) {
    _name.text = cf.name;
    _port.text = '${cf.udpPort}';
    _apSsid.text = cf.apSsid;
    _apPass.clear();
    _apIp.text = cf.apIp;
    _staSsid.text = cf.staSsid;
    _staPass.clear();
    _staIp.text = cf.staIp;
    _staGateway.text = cf.staGateway;
    _staSubnet.text = cf.staSubnet;
    _staDns.text = cf.staDns;
  }

  /// Sửa phần kết nối WiFi của hồ sơ đã lưu (màn Cấu hình tự nạp lại khi quay về)
  Future<void> _patchProfile(void Function(WifiConn w, CarProfile p) edit) async {
    final fresh = widget.repo.get(widget.profileId);
    if (fresh == null) return;
    final before = jsonEncode(fresh.toJson());
    edit(fresh.wifi ??= WifiConn(), fresh);
    if (jsonEncode(fresh.toJson()) != before) await widget.repo.save(fresh, touch: false);
  }

  // ---------------- Lệnh ----------------
  Future<bool> _confirm(String title, String body, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _info(String title, String body) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu'))],
        ),
      );

  /// Hướng dẫn nối lại sau khi xe khởi động lại với cấu hình `cf`
  String _nextSteps(NetConfig cf) {
    if (cf.bootMode == NetMode.ap) {
      return 'Xe phát WiFi "${cf.apSsid}". Nối điện thoại vào WiFi này rồi bấm Kết nối '
          '(IP ${cf.apIp}, port ${cf.udpPort}).';
    }
    return 'Xe vào router "${cf.staSsid}". Nối điện thoại vào cùng router (băng 2.4 hay 5 GHz đều được) '
        'rồi bấm Kết nối, app tự tìm xe trong mạng${cf.staDhcp ? '' : ' (IP ${cf.staIp})'}.\n\n'
        'Nếu 15 giây không vào được router, xe tự phát lại WiFi "${cf.apSsid}" để bạn sửa.';
  }

  Future<bool> _guard() async {
    if (c.arm.armed) {
      _snack('DISARM trước khi đổi mạng của xe');
      return false;
    }
    return true;
  }

  Future<void> _apply() async {
    final cf = cfg!, old = saved!, st = status!;
    final errors = cf.validate();
    if (errors.isNotEmpty) {
      _snack(errors.values.first);
      return;
    }
    if (!await _guard()) return;
    final ok = await _confirm(
      'Lưu vào xe và khởi động lại?',
      'Xe khởi động lại (khoảng 3 giây) và ngắt kết nối với app.\n\n${_nextSteps(cf)}',
      'Lưu & khởi động lại',
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      await c.applyNetConfig(cf);
    } catch (e) {
      _snack(_msg(e));
      if (mounted) setState(() => busy = false);
      return;
    }
    await _patchProfile((w, p) {
      w
        ..carId = st.id
        ..port = cf.udpPort;
      if (cf.bootMode == NetMode.ap) {
        w
          ..ip = cf.apIp
          ..ssid = cf.apSsid;
      } else {
        if (!cf.staDhcp) w.ip = cf.staIp; // IP động: app dò theo mã xe khi kết nối
        w.ssid = cf.staSsid;
      }
      final b = p.ble;
      if (b != null && b.deviceName == old.name) b.deviceName = cf.name;
    });
    if (!mounted) return;
    await _info('Đã lưu cấu hình mạng', _nextSteps(cf));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _enterSetup() async {
    final cf = saved!, st = status!;
    if (!await _guard()) return;
    final ok = await _confirm(
      'Vào chế độ cấu hình?',
      'Xe khởi động lại và phát WiFi tạm "${st.setupSsid}" (mật khẩu giống WiFi riêng của xe), '
          'IP ${cf.apIp}. Ở chế độ này xe không nhận lệnh lái.\n\n'
          'Tự thoát sau 5 phút không có điện thoại nối. Cũng vào được bằng cách giữ nút BOOT trên xe 3 giây.',
      'Khởi động lại',
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      await c.enterNetSetup();
    } catch (e) {
      _snack(_msg(e));
      if (mounted) setState(() => busy = false);
      return;
    }
    await _patchProfile((w, p) => w
      ..carId = st.id
      ..ip = cf.apIp
      ..port = cf.udpPort);
    if (!mounted) return;
    await _info('Xe đang vào chế độ cấu hình',
        'Nối điện thoại vào WiFi "${st.setupSsid}", rồi ở màn Xe của tôi bấm Kết nối và mở lại Mạng của xe.');
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reset() async {
    final st = status!;
    if (!await _guard()) return;
    final ok = await _confirm(
      'Khôi phục mạng mặc định?',
      'Xe quên WiFi router và về mặc định: phát WiFi "RC-CAR", mật khẩu 12345678, IP 192.168.4.1, port 4210. '
          'Xe khởi động lại và ngắt kết nối.',
      'Khôi phục',
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      await c.resetNetConfig();
    } catch (e) {
      _snack(_msg(e));
      if (mounted) setState(() => busy = false);
      return;
    }
    final d = NetConfig();
    await _patchProfile((w, p) => w
      ..carId = st.id
      ..ip = d.apIp
      ..port = d.udpPort
      ..ssid = d.apSsid);
    if (!mounted) return;
    await _info('Đã khôi phục mạng mặc định', _nextSteps(d));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _onPop(bool didPop, Object? _) async {
    if (didPop) return;
    final leave = await _confirm('Bỏ thay đổi?', 'Các thay đổi chưa lưu vào xe sẽ bị mất.', 'Bỏ');
    if (leave && mounted) Navigator.pop(context);
  }

  // ---------------- Giao diện ----------------
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final ready = _connected && cfg != null;
        return PopScope(
          canPop: !_dirty || !_connected,
          onPopInvokedWithResult: _onPop,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Mạng của xe'),
              actions: [
                if (_connected)
                  IconButton(
                    tooltip: 'Đọc lại từ xe',
                    onPressed: busy ? null : _load,
                    icon: const AppIcon(AppIcons.refresh),
                  ),
                if (ready)
                  PopupMenuButton<String>(
                    icon: const AppIcon(AppIcons.more),
                    enabled: !busy,
                    onSelected: (v) => v == 'setup' ? _enterSetup() : _reset(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'setup',
                          child: ListTile(leading: AppIcon(AppIcons.wifi), title: Text('Chế độ cấu hình (WiFi tạm)'))),
                      PopupMenuItem(
                          value: 'reset',
                          child: ListTile(leading: AppIcon(AppIcons.reset), title: Text('Khôi phục mạng mặc định'))),
                    ],
                  ),
              ],
            ),
            body: !_connected
                ? _notConnected()
                : cfg == null
                    ? _loading()
                    : _form(),
            bottomNavigationBar: ready ? _bottomBar() : null,
          ),
        );
      },
    );
  }

  Widget _notConnected() {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(AppIcons.wifi, size: 48, color: t.textMuted),
          const SizedBox(height: Gap.l),
          Text('Chưa kết nối xe', style: AppText.headline.copyWith(color: t.text)),
          const SizedBox(height: Gap.s),
          Text(
            'Cấu hình mạng lưu trên xe, không nằm trong hồ sơ. '
            'Kết nối xe (WiFi hoặc Bluetooth) ở màn Xe của tôi rồi mở lại màn này.',
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: t.textBody),
          ),
        ]),
      ),
    );
  }

  Widget _loading() {
    final t = context.tokens;
    final err = loadError;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: err == null
            ? const CircularProgressIndicator()
            : Column(mainAxisSize: MainAxisSize.min, children: [
                AppIcon(AppIcons.warning, size: 40, color: t.warn),
                const SizedBox(height: Gap.m),
                Text('Không đọc được cấu hình mạng', style: AppText.title.copyWith(color: t.text)),
                const SizedBox(height: Gap.xs),
                Text('$err\nFirmware trên xe cần bản có "Mạng của xe".',
                    textAlign: TextAlign.center, style: AppText.label.copyWith(color: t.textMuted)),
                const SizedBox(height: Gap.l),
                FilledButton.icon(
                  onPressed: busy ? null : _load,
                  icon: const AppIcon(AppIcons.refresh, mini: true),
                  label: const Text('Thử lại'),
                ),
              ]),
      ),
    );
  }

  Widget _bottomBar() {
    final t = context.tokens;
    final errors = cfg!.validate();
    final setupMode = status?.mode == NetMode.setup;
    final canSave = errors.isEmpty && !busy && (_dirty || setupMode);
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
        padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.s),
                child: Row(children: [
                  AppIcon(AppIcons.warning, color: t.bad, mini: true),
                  const SizedBox(width: Gap.s),
                  Expanded(child: Text(errors.values.first, style: AppText.label.copyWith(color: t.bad))),
                ]),
              ),
            FilledButton.icon(
              onPressed: canSave ? _apply : null,
              icon: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const AppIcon(AppIcons.save, mini: true),
              label: Text(setupMode && !_dirty ? 'Thoát chế độ cấu hình' : 'Lưu vào xe & khởi động lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint(String s) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: Text(s, style: AppText.label.copyWith(color: context.tokens.textMuted, fontSize: 13)),
      );

  Widget _heading(String s) => Padding(
        padding: const EdgeInsets.only(top: Gap.l, bottom: Gap.s),
        child: Text(s, style: AppText.title.copyWith(color: context.tokens.text)),
      );

  Widget _field(
    TextEditingController ctrl,
    String label,
    String? error,
    ValueChanged<String> onChanged, {
    String? hint,
    String? helper,
    TextInputType? keyboard,
    bool obscure = false,
    bool enabled = true,
    Widget? suffix,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: TextField(
          controller: ctrl,
          enabled: enabled && !busy,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: !obscure,
          keyboardType: keyboard,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            helperText: helper,
            errorText: error,
            suffixIcon: suffix,
          ),
          onChanged: (v) => setState(() => onChanged(v)),
        ),
      );

  Widget _eye(bool shown, VoidCallback toggle) => IconButton(
        tooltip: shown ? 'Ẩn' : 'Hiện',
        onPressed: toggle,
        icon: AppIcon(shown ? AppIcons.hideSecret : AppIcons.showSecret, mini: true),
      );

  static const _ipKeyboard = TextInputType.numberWithOptions(decimal: true);

  Widget _form() {
    final cf = cfg!;
    final e = cf.validate();
    final sta = cf.bootMode == NetMode.sta;
    final staOpen = cf.staPass == '';
    return ListView(
      padding: const EdgeInsets.all(Gap.l),
      children: [
        _statusCard(),
        _heading('Khi bật nguồn'),
        SegmentedButton<NetMode>(
          segments: const [
            ButtonSegment(value: NetMode.ap, label: Text('WiFi riêng (AP)')),
            ButtonSegment(value: NetMode.sta, label: Text('Vào router nhà')),
          ],
          selected: {cf.bootMode},
          onSelectionChanged: busy ? null : (s) => setState(() => cf.bootMode = s.first),
        ),
        const SizedBox(height: Gap.s),
        _hint(sta
            ? 'Xe vào WiFi router (chỉ băng 2.4 GHz). Điện thoại vào cùng router, băng 2.4 hay 5 GHz đều được, '
                'và vẫn có internet. Không vào được router sau 15 giây thì xe tự phát WiFi riêng.'
            : 'Xe tự phát WiFi, điện thoại nối thẳng vào xe. Dùng ngoài trời, không cần router.'),

        _heading('Chung'),
        _field(_name, 'Tên thiết bị', e['name'], (v) => cf.name = v.trim(),
            helper: 'Tên Bluetooth và tên của xe trong mạng router'),
        _field(_port, 'Port UDP', e['udpPort'], (v) => cf.udpPort = int.tryParse(v.trim()) ?? 0,
            keyboard: TextInputType.number, helper: 'Mặc định 4210. Port $discoveryPort dành cho tìm xe'),

        _heading('WiFi riêng của xe (AP)'),
        _field(_apSsid, 'Tên WiFi (SSID)', e['apSsid'], (v) => cf.apSsid = v),
        _field(
          _apPass,
          'Mật khẩu',
          e['apPass'],
          (v) => cf.apPass = v.isEmpty ? null : v,
          hint: 'Để trống = giữ mật khẩu hiện tại',
          helper: '8–63 ký tự. Cũng là mật khẩu WiFi tạm ở chế độ cấu hình',
          obscure: !showApPass,
          suffix: _eye(showApPass, () => setState(() => showApPass = !showApPass)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.m),
          child: DropdownButtonFormField<int>(
            key: ValueKey('ch-${saved!.signature}'), // đọc lại từ xe thì dựng lại với giá trị mới
            initialValue: cf.apChannel.clamp(1, 13).toInt(),
            decoration: InputDecoration(labelText: 'Kênh WiFi', errorText: e['apChannel']),
            items: [for (var ch = 1; ch <= 13; ch++) DropdownMenuItem(value: ch, child: Text('Kênh $ch'))],
            onChanged: busy ? null : (v) => setState(() => cf.apChannel = v ?? 1),
          ),
        ),
        _field(_apIp, 'IP của xe', e['apIp'], (v) => cf.apIp = v.trim(),
            keyboard: _ipKeyboard, helper: 'IP tĩnh, mạng /24. Mặc định 192.168.4.1'),

        _heading('WiFi router'),
        _hint('Xe chỉ dùng được WiFi 2.4 GHz. Nếu router đặt tên riêng cho hai băng, chọn tên 2.4 GHz.'),
        _field(_staSsid, 'Tên WiFi router (SSID)', e['staSsid'], (v) => cf.staSsid = v),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Mạng không có mật khẩu'),
          value: staOpen,
          onChanged: busy
              ? null
              : (v) => setState(() {
                    cf.staPass = v == true ? '' : (_staPass.text.isEmpty ? null : _staPass.text);
                  }),
        ),
        _field(
          _staPass,
          'Mật khẩu router',
          e['staPass'],
          (v) => cf.staPass = v.isEmpty ? null : v,
          hint: cf.staHasPass ? 'Để trống = giữ mật khẩu hiện tại' : null,
          enabled: !staOpen,
          obscure: !showStaPass,
          suffix: _eye(showStaPass, () => setState(() => showStaPass = !showStaPass)),
        ),
        Text('Địa chỉ IP của xe trong mạng router', style: AppText.label.copyWith(color: context.tokens.text)),
        const SizedBox(height: Gap.s),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Động (DHCP)')),
            ButtonSegment(value: false, label: Text('Tĩnh')),
          ],
          selected: {cf.staDhcp},
          onSelectionChanged: busy ? null : (s) => setState(() => cf.staDhcp = s.first),
        ),
        const SizedBox(height: Gap.s),
        if (cf.staDhcp)
          _hint('Router tự cấp IP. App tự tìm xe trong mạng theo mã xe khi kết nối.')
        else ...[
          const SizedBox(height: Gap.s),
          _field(_staIp, 'IP tĩnh', e['staIp'], (v) => cf.staIp = v.trim(), keyboard: _ipKeyboard, hint: '192.168.1.50'),
          _field(_staGateway, 'Gateway', e['staGateway'], (v) => cf.staGateway = v.trim(),
              keyboard: _ipKeyboard, hint: '192.168.1.1', helper: 'Thường là IP của router'),
          _field(_staSubnet, 'Subnet mask', e['staSubnet'], (v) => cf.staSubnet = v.trim(),
              keyboard: _ipKeyboard, hint: '255.255.255.0'),
          _field(_staDns, 'DNS (tuỳ chọn)', e['staDns'], (v) => cf.staDns = v.trim(),
              keyboard: _ipKeyboard, helper: 'Để trống = dùng gateway'),
          _hint('Chọn IP nằm ngoài dải router tự cấp để không trùng máy khác.'),
        ],
      ],
    );
  }

  Widget _statusCard() {
    final t = context.tokens;
    final st = status!;
    final cf = saved!;
    String two(int n) => n.toString().padLeft(2, '0');
    final lines = <String>[
      'IP ${st.ip} · port ${cf.udpPort}',
      if (st.mode == NetMode.sta) 'Router "${cf.staSsid}"${st.rssi != 0 ? ' · sóng ${st.rssi} dBm' : ''}',
      if (st.mode == NetMode.ap) 'Phát WiFi "${cf.apSsid}" · ${st.clients} máy đang nối',
      if (st.mode == NetMode.setup)
        'Phát WiFi tạm "${st.setupSsid}" · tự thoát sau ${st.setupLeftS ~/ 60}:${two(st.setupLeftS % 60)} nếu không có máy nối',
      if (st.mode != NetMode.sta && cf.staSsid.isNotEmpty && st.staResult != StaResult.none)
        'Router "${cf.staSsid}": ${st.staResult.label}',
      'Mã xe ${st.id}',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: Gap.s, runSpacing: Gap.xs, children: [
              Pill(color: st.mode == NetMode.setup ? t.warn : t.ok, label: 'Đang chạy: ${st.mode.label}'),
              if (st.fellBack) Pill(color: t.bad, label: 'Không vào được router: ${st.staResult.label}'),
            ]),
            const SizedBox(height: Gap.s),
            for (final l in lines) Text(l, style: AppText.label.copyWith(color: t.textBody)),
            if (st.fellBack) ...[
              const SizedBox(height: Gap.s),
              Text('Xe đang phát WiFi riêng để bạn sửa thông tin router bên dưới.',
                  style: AppText.label.copyWith(color: t.bad, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}
