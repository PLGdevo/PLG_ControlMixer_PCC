/// Ngưỡng màu ô Ping (F6). Lưu trong hồ sơ để dùng khi lái.
class PingConfig {
  int greenRttMs;
  double greenLossPct;
  int yellowRttMs;
  double yellowLossPct;
  int weakAfterMs; // đỏ kéo dài bao lâu thì hiện "Kết nối yếu"

  PingConfig({
    this.greenRttMs = 60,
    this.greenLossPct = 2,
    this.yellowRttMs = 150,
    this.yellowLossPct = 10,
    this.weakAfterMs = 3000,
  });

  Map<String, dynamic> toJson() => {
        'greenRttMs': greenRttMs,
        'greenLossPct': greenLossPct,
        'yellowRttMs': yellowRttMs,
        'yellowLossPct': yellowLossPct,
        'weakAfterMs': weakAfterMs,
      };

  factory PingConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return PingConfig();
    return PingConfig(
      greenRttMs: j['greenRttMs'] as int? ?? 60,
      greenLossPct: (j['greenLossPct'] as num?)?.toDouble() ?? 2,
      yellowRttMs: j['yellowRttMs'] as int? ?? 150,
      yellowLossPct: (j['yellowLossPct'] as num?)?.toDouble() ?? 10,
      weakAfterMs: j['weakAfterMs'] as int? ?? 3000,
    );
  }
}
