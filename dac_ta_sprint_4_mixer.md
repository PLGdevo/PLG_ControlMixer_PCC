# Đặc tả Sprint 4 — Input · Condition · Mixer · ARM

> Mô hình điều khiển mới: người dùng tạo **Input**, dùng **luật mix** có **Condition** để quyết định Input tác động lên kênh nào, rồi **kênh** đổi sang µs gửi xuống xe.
>
> Phiên bản: 1.1 · Ngày: 25/09/2026 · Dự án: `rc_car` · Thay thế: B1 (đường tính), B2–B4 (gán kênh 1:1), G1–G6 (`MixRule`), phần "Gán kênh" của H3 trong `dac_ta_sprint_3.md`
>
> **Thay đổi ở bản 1.1 (chốt khi làm):** giới hạn 64 luật / 32 Condition đặt tên / 48 Input (đủ chỗ cho hồ sơ Sprint 3 chuyển sang); `hyst` 0…200; "tầng" chỉ tính AND/OR/NOT; J4 dùng điều kiện có trễ viết thẳng trong luật thay cho Condition đặt tên, thêm luật hằng 0% cho kênh nhận luật `max`; tên file theo mã đã viết (P1); ghi rõ cầu nối giao thức v1 (R1).
>
> Giữ nguyên từ Sprint 3: nguyên tắc 0.5 (app giữ cấu hình, xe chỉ nhận 10 kênh µs + failsafe), giao thức C1, failsafe E5–E6, bố cục H1–H6, tự về H3b.

---

## 0. Tổng quan

### 0.1 Mục tiêu

1. UI chỉ tạo **Input** (cần gạt, nút, công tắc, núm). UI **không** quyết định Input đi vào kênh nào.
2. **Luật mix** gồm Nguồn → Condition → Weight / Offset / Curve / Min–Max → Kênh đích. Một Input có thể đi vào nhiều kênh; một kênh có thể nhận nhiều luật.
3. Trường hợp *"A = 1 thì Slider X → CH1, A = 0 thì Slider X → CH8"* chỉ là **cấu hình** (hai luật), không phải code riêng.
4. Có **trạng thái ARM**: vừa kết nối xong thì xe chưa nhận lệnh lái.
5. Hồ sơ Sprint 3 được **tự chuyển đổi** sang mô hình mới, không mất cấu hình.

### 0.2 Kiến trúc

```
 Bố cục màn Lái (H)          Hồ sơ (JSON)
 ControlItem ──bind──┐          │
                     ▼          ▼
               INPUT MANAGER  ◄─ inputs[]
                     │  giá trị Input (%, trạng thái)
                     ▼
              CONDITION ENGINE ◄─ conditions[] (có hysteresis)
                     │  đúng / sai cho từng luật
                     ▼
               MIXER ENGINE   ◄─ mixer[] (priority, combine, khoá an toàn)
                     │  CH1…CH10 (%, −100…+100)
                     ▼
               CHANNEL STAGE  ◄─ channels[] (hộp số, reverse, trim, Min/Center/Max)
                     │  CH1…CH10 (µs)
                     ▼
                ARM GATE      ◄─ trạng thái kết nối / ARM
                     │  chưa ARM → gửi failsafeUs
                     ▼
              PROTOCOL ENGINE → CONTROL (UDP / BLE)
```

Cả chuỗi chạy trong app, mỗi chu kỳ gửi (**25 ms**, giữ nhịp hiện tại). Xe không đổi gì (C2): vẫn chỉ xuất µs và giữ failsafe.

### 0.3 Những gì thay đổi so với Sprint 3

| Sprint 3 | Sprint 4 |
|---|---|
| Phần tử gán **1:1** vào kênh (`ControlItem.channel`) | Phần tử gắn vào **Input** (`ControlItem.inputId`); luật mix nối Input → kênh |
| Mix đọc **kênh** (CH1 ≥ 80% → CH3) | Luật đọc **Input**. Không còn vòng lặp kênh → kênh, bỏ bước dò chu trình G4 |
| Luật 4 loại: threshold / linear / curve / select | Một loại luật chung + Condition. Threshold = Condition có hysteresis; select = hai luật có khoá an toàn |
| `gateCh > 0%` | Condition đầy đủ: `== != > < >= <=`, `AND / OR / NOT`, tham chiếu Condition đặt tên |
| Mode override / add / max | Combine `replace / add / multiply / max / min` + `priority` |
| `offValuePct` trên kênh | Mức bật/tắt nằm trên Input (`levels`) |
| Hộp số áp **trước** mix | Hộp số áp ở Channel Stage, **sau** mixer, lên kênh Ga |
| Kết nối xong là lái | Phải **ARM** mới gửi lệnh lái |

### 0.4 Phạm vi

| Trong phạm vi | Ngoài phạm vi (ghi lại để mở rộng sau) |
|---|---|
| Input từ phần tử trên màn Lái; Input hằng số | Input từ cảm biến điện thoại (gyro, gia tốc), GPS, telemetry |
| UDP, BLE (như hiện tại) | UART, MAVLink, SBUS/CRSF (Protocol Engine để sẵn interface) |
| Nhịp gửi 25 ms | 50 / 100 / 200 Hz |
| Tối đa 64 luật, 32 Condition đặt tên, 48 Input | — |

---

## 1. Nhóm I — Input

### I1. Mô hình

```dart
class InputDef {
  String id;            // duy nhất trong hồ sơ, [a-z0-9_]{1,24}, vd "slider_x", "btn_a"
  String name;          // "Slider X", "Nút A"
  InputType type;       // axis | binary | ternary | constant
  AxisRange range;      // chỉ axis: bipolar (−100…+100) | unipolar (0…100)
  InputLevels levels;   // chỉ binary / ternary: % đưa vào mixer ở từng trạng thái
  double constPct;      // chỉ constant: −100…+100
}

class InputLevels {
  double offPct = -100; // binary: tắt; ternary: nấc trái
  double midPct = 0;    // ternary: nấc giữa
  double onPct  = 100;  // binary: bật; ternary: nấc phải
}
```

- Input thuộc **hồ sơ** (`CarProfile.inputs`), không thuộc bố cục. Nhiều bố cục dùng chung một Input, nên đổi bố cục không phải cấu hình lại mix.
- `constant` là Input ảo không cần phần tử trên màn (vd luật "CH5 = 30% khi A bật").
- Giới hạn 48 Input.

### I2. Loại Input và phần tử tương thích

| `type` | Trạng thái (dùng trong Condition) | Giá trị (đưa vào mixer) | Phần tử gắn được (B2) |
|---|---|---|---|
| `axis` bipolar | −100…+100 | −100…+100 % | Cần gạt ngang/dọc, một trục của cần 2 trục, núm xoay |
| `axis` unipolar | 0…100 | 0…100 % | Như trên. Vị trí thấp nhất của cần = 0 |
| `binary` | 0 / 1 | `offPct` / `onPct` | Nút nhấn giữ, nút bật/tắt |
| `ternary` | −1 / 0 / 1 | `offPct` / `midPct` / `onPct` | Công tắc 3 nấc |
| `constant` | = `constPct` | `constPct` | Không cần phần tử |

- **Trạng thái** và **giá trị** tách riêng: Condition viết `A == 1` theo trạng thái, không phụ thuộc người dùng đặt mức tắt là −100% hay 0%.
- Trục unipolar: bộ chuẩn hoá đổi vị trí cần −100…+100 thành 0…100 (`(p + 100) / 2`). Tự về (H3b) vẫn tính trên vị trí cần.

### I3. Gắn phần tử vào Input

```dart
class ControlItem {
  ...
  String? inputId;    // thay cho `channel`
  String? inputIdY;   // chỉ stick2D, thay cho `channelY`
}
```

- Một Input có tối đa **một** phần tử trên một bố cục (giống B4, nhưng áp cho Input).
- Input không có phần tử trên bố cục đang dùng thì giữ **giá trị nghỉ**: axis = vị trí `targetPct` mặc định (0%, unipolar = 0), binary = tắt, ternary = giữa.
- Phần tử chưa gắn Input hiện *"Chưa gắn Input"* và không tác động gì.

### I4. Chuẩn hoá giá trị

Mixer làm việc trên **%** (số thực, −100…+100). Không dùng thang 0…1 hay −1…+1 bên trong, để UI, JSON và công thức cùng một đơn vị. Làm tròn chỉ xảy ra ở Channel Stage khi đổi sang µs.

---

## 2. Nhóm K — Condition

### K1. Biểu thức

Condition là cây biểu thức, lưu JSON:

```jsonc
{ "op": "cmp", "input": "btn_a", "cmp": "==", "value": 1 }
{ "op": "cmp", "input": "slider_x", "cmp": ">=", "value": 80, "hyst": 10 }
{ "op": "and", "args": [ <expr>, <expr>, ... ] }
{ "op": "or",  "args": [ <expr>, <expr>, ... ] }
{ "op": "not", "arg": <expr> }
{ "op": "ref", "id": "cond_arm_ok" }       // tham chiếu Condition đặt tên (K3)
{ "op": "true" }                            // luôn đúng (mặc định của luật)
```

| Toán tử `cmp` | `==` `!=` `>` `<` `>=` `<=` |
|---|---|
| So với | **Trạng thái** của Input (I2) |
| `==` / `!=` trên axis | So với sai số ±0,5% |

- Giới hạn: lồng tối đa 4 tầng AND / OR / NOT (phép so sánh, `ref`, `true` không tính tầng), tối đa 8 phép `cmp` trong một biểu thức.
- `input` phải tồn tại trong hồ sơ; xoá Input đang được dùng thì app liệt kê các luật/Condition bị ảnh hưởng và hỏi xác nhận (luật bị ảnh hưởng chuyển sang tắt).

### K2. Hysteresis (thay cho luật threshold G2a)

- `hyst` chỉ dùng với `>`, `>=`, `<`, `<=`; mặc định 0; khoảng 0…200.
- `>= 80, hyst 10`: chuyển **đúng** khi trạng thái ≥ 80; chuyển **sai** khi < 70; ở giữa thì **giữ kết quả trước**. Ban đầu là sai.
- `<= 20, hyst 10`: đúng khi ≤ 20; sai khi > 30.
- Mỗi `cmp` có hysteresis giữ trạng thái riêng trong RAM, reset về sai khi: mất kết nối, DISARM, thoát màn Lái, xe báo failsafe.

Ví dụ G2a của Sprint 3 (CH1 ≥ 80% → CH3 = 100%, < 70% → 0%) viết lại:

| Luật | Nguồn | Condition | Kết quả |
|---|---|---|---|
| 1 | `const 0` | `true` | CH3 = 0% |
| 2 | `const 100` | `steer >= 80, hyst 10` | CH3 = 100% (`replace`, priority cao hơn luật 1) |

Bảng kiểm tra G2a (0→75→82→72→69→78) giữ nguyên kết quả.

### K3. Condition đặt tên

```dart
class ConditionDef { String id; String name; Expr expr; }
```

- Dùng lại một điều kiện ở nhiều luật (vd `cond_emergency`), sửa một chỗ.
- `ref` không được tạo vòng (A tham chiếu B, B tham chiếu A): app báo lỗi và không cho lưu.
- Condition đặt tên có hysteresis thì mọi luật tham chiếu dùng **chung** một trạng thái.
- Giới hạn 32 Condition đặt tên.
- AND / OR luôn tính **mọi** nhánh (không dừng sớm) để trạng thái trễ của từng nhánh luôn được cập nhật.

---

## 3. Nhóm M — Mixer

### M1. Luật mix

```dart
class MixRule {
  String id;
  String name;               // tuỳ chọn; trống thì dùng mô tả tự sinh (M6)
  bool enabled;
  String source;             // inputId (kể cả constant)
  Expr condition;            // mặc định {"op":"true"}
  double weightPct;          // −200…+200, mặc định 100
  double offsetPct;          // −100…+100, mặc định 0
  Curve curve;               // linear | expo(k) | points(5 điểm)
  double minPct, maxPct;     // −100…+100, mặc định −100 / +100, min < max
  int destCh;                // 1..10
  Combine combine;           // replace | add | multiply | max | min
  int priority;              // 0..9, mặc định 0
  SwitchSafety safety;       // xem M4
}

class Curve {
  CurveType type;            // linear | expo | points
  double expoPct;            // expo: −100…+100
  List<double> points;       // points: 5 điểm tại −100, −50, 0, 50, 100
}

class SwitchSafety {
  bool requireNeutral;       // mặc định: true nếu nguồn là axis, false nếu không
  double deadzonePct;        // mặc định 5
}
```

Giới hạn **64 luật** (`MixRule.maxRules`); đủ thì khoá nút *Thêm luật*.

### M2. Tính một luật

```
if !enabled                    → bỏ qua
active = safety.apply(condition)   // M4
if !active                     → bỏ qua
v = value(source)              // % theo I2
v = v × weight / 100 + offset
v = curve(v)                   // expo / nội suy 5 điểm; linear = giữ nguyên
v = clamp(v, minPct, maxPct)
```

Thứ tự Weight → Offset → Curve → Min/Max giống đề xuất ban đầu. Curve nhận và trả −100…+100; ngoài khoảng đó thì kẹp trước khi áp curve.

### M3. Gộp nhiều luật vào một kênh

- Với mỗi kênh, lấy các luật có `destCh` là kênh đó, sắp theo **`priority` tăng dần**, cùng priority thì theo **thứ tự danh sách**.
- Kênh bắt đầu ở trạng thái **chưa có giá trị**. Lần lượt áp từng luật đang active:

| `combine` | Kênh chưa có giá trị | Kênh đã có giá trị `c` |
|---|---|---|
| `replace` | `v` | `v` (bỏ giá trị trước) |
| `add` | `v` | `c + v` |
| `multiply` | giữ chưa có giá trị | `c × v / 100` |
| `max` | `v` | `max(c, v)` |
| `min` | `v` | `min(c, v)` |

- Hết luật: kênh chưa có giá trị → **0%** (tức Center, giống Sprint 3). Rồi kẹp −100…+100.
- Vì luật sau thắng khi `replace`, luật khẩn cấp đặt `priority` cao + `replace` sẽ đè mọi thứ khi Condition của nó đúng:

| Luật | Nguồn | Condition | Combine | Priority |
|---|---|---|---|---|
| Ga | `throttle` | `true` | `replace` | 0 |
| Lái trộn vào CH1 | `steer` × 30% | `true` | `add` | 0 |
| Khẩn cấp | `const 0` | `btn_stop == 1` | `replace` | 9 |

### M4. Khoá an toàn khi đổi đích (thay luật select G2d)

Vấn đề: *A = 1 → Slider X → CH1, A = 0 → Slider X → CH8*. Đang ga 70% mà gạt A thì CH8 nhảy thẳng lên 70%.

Quy tắc khi `safety.requireNeutral = true`:

- Mỗi luật giữ `activeLatched` (ban đầu = kết quả Condition lúc ARM).
- Condition đổi kết quả mà nguồn **đang lệch tâm** (|giá trị| > `deadzonePct`, với unipolar thì > `deadzonePct` tính từ 0) thì **giữ `activeLatched` cũ**. Luật hiện *"Chờ về giữa"*.
- Nguồn về trong vùng chết thì `activeLatched` nhận kết quả Condition mới.
- Hai luật dùng chung nguồn nên chuyển **cùng một lúc** (cùng thấy nguồn về giữa trong cùng chu kỳ). Không có chu kỳ nào cả hai cùng active hoặc cùng không active trừ lúc chờ.
- Failsafe, DISARM, mất kết nối: huỷ trạng thái chờ, `activeLatched` tính lại từ đầu khi ARM.
- Luật có `priority` ≥ 8 **không được** bật khoá an toàn (dành cho luật khẩn cấp: phải tác động ngay).

Trường hợp A / Slider X:

```jsonc
{ "id": "r_ch1", "source": "slider_x", "condition": {"op":"cmp","input":"btn_a","cmp":"==","value":1},
  "weightPct": 100, "offsetPct": 0, "destCh": 1, "combine": "replace", "priority": 0,
  "safety": {"requireNeutral": true, "deadzonePct": 5} }
{ "id": "r_ch8", "source": "slider_x", "condition": {"op":"cmp","input":"btn_a","cmp":"==","value":0},
  "weightPct": 100, "offsetPct": 0, "destCh": 8, "combine": "replace", "priority": 0,
  "safety": {"requireNeutral": true, "deadzonePct": 5} }
```

Bảng dưới chỉ xét hai luật này (không có luật lái `r_steer` như ở J2):

| Bước | A | Slider X | CH1 | CH8 | Ghi chú |
|---|---|---|---|---|---|
| 1 | 1 | 70 | 70 | 0 | |
| 2 | 0 | 70 | 70 | 0 | Chờ về giữa |
| 3 | 0 | 30 | 30 | 0 | Vẫn chờ |
| 4 | 0 | 3 | 0 | 3 | Về vùng chết → chuyển |
| 5 | 0 | 70 | 0 | 70 | |

(`slider_x` ở đây là bipolar. Nếu unipolar 0…100 thì CH1/CH8 = 0% nghĩa là Center, còn 100% là Max; muốn cần đẩy từ Min tới Max thì đặt `weight 200, offset −100` — nút *Toàn dải* trong trình sửa luật đặt sẵn hai số này.)

### M5. Hiệu năng

- 64 luật, 32 Condition đặt tên, 48 Input: tính một chu kỳ ≤ **2 ms** trên Android tầm trung (như G1).
- Không cấp phát đối tượng mới trong vòng tính: biểu thức được **biên dịch** một lần khi nạp hồ sơ thành danh sách phẳng; mọi trạng thái (hysteresis, latch) nằm trong mảng có sẵn.

### M6. Mô tả tự sinh

| Luật | Mô tả |
|---|---|
| Không điều kiện | `Slider X → CH1` |
| Có điều kiện | `Slider X → CH1 · khi Nút A = 1` |
| Weight/offset khác mặc định | `Slider X × 50% + 10% → CH1` |
| Hằng số | `CH3 = 100% · khi Steer ≥ 80% (trễ 10%)` |
| Khoá an toàn | thêm ` · chờ về giữa` |

---

## 4. Nhóm O — Channel Stage và Output

### O1. Kênh

Giữ `ChannelConfig` của Sprint 3 (index, name, min/center/max, trim, offset, reverse, failsafeUs, enabled). **Bỏ** `offValuePct` (chuyển sang `InputLevels`).

- `enabled = false`: kênh luôn ra `failsafeUs` và bị bỏ qua trong mixer (luật ghi vào kênh tắt hiện cảnh báo vàng).
- Kênh Ga và Lái vẫn là **CH2** và **CH1** (hằng số `CarProfile.throttleCh`, `steeringCh`); dùng cho hộp số, H5 và ARM.

### O2. Đổi % sang µs

```
p = mixer[ch]                               // −100…+100
nếu ch == throttleCh: p = p × maxThrottle[gear] / 100    // hộp số (B5), sau mixer
nếu reverse: p = −p
center = clamp(centerUs + trimUs + offsetUs, minUs, maxUs)
us = p ≥ 0 ? center + p/100 × (maxUs − center) : center + p/100 × (center − minUs)
us = clamp(round(us), minUs, maxUs)
```

Giống `OutputPipeline.toUs` hiện tại; chỉ khác vị trí áp hộp số.

### O3. Failsafe

Không đổi: `failsafeUs` theo µs cho từng kênh, `failsafeTimeoutMs`, đồng bộ bằng `FS_WRITE` (E5–E6). Không hỗ trợ failsafe tính theo % vì xe không biết cấu hình kênh.

### O4. Protocol Engine

```dart
abstract class OutputProtocol {
  String get name;                    // "RC v2 / UDP", "RC v2 / BLE"
  Duration get period;                // 25 ms
  Future<void> sendControl(int seq, List<int> us);   // 10 kênh µs
  Future<bool> syncFailsafe(int timeoutMs, List<int> fsUs);
}
```

- Sprint 4 có hai lớp: `RcV2Udp`, `RcV2Ble` (gói C1). `RcV1Legacy` cho firmware cũ (2 kênh).
- UART / MAVLink / SBUS là lớp mới cài interface này, không đụng mixer.

---

## 5. Nhóm R — Trạng thái kết nối và ARM

### R1. Máy trạng thái

```
DISCONNECTED ──kết nối──► CONNECTED ──FS_WRITE/FS_ACK ok──► READY ──ARM──► ARMED
     ▲                        │                                │   ◄─DISARM─┘
     └──── mất kết nối ◄──────┴──── đồng bộ lỗi 3 lần ─────────┘      │
                                   (ở lại CONNECTED, không cho ARM)   │
     ◄──────────────────────── mất kết nối / failsafe ───────────────┘
```

| Trạng thái | Gói gửi xuống xe | Màn Lái |
|---|---|---|
| DISCONNECTED | Không | Huy hiệu "Chưa kết nối" |
| CONNECTED | Không gửi `CONTROL` (đang đồng bộ failsafe) | "Đang đồng bộ…" |
| READY | `CONTROL` với **`failsafeUs`** của từng kênh | Nút **ARM**, phần tử vẫn kéo được để kiểm tra |
| ARMED | `CONTROL` với kết quả mixer | Lái bình thường; nút `ARMED` màu `accent` |

**Cầu nối giao thức v1** (tới khi có C1–C2): xe chỉ nhận CH1/CH2 dạng −1…+1 và tự áp servo, hộp số, failsafe. READY gửi trung tính (0, 0); ARMED gửi kết quả mixer của CH1/CH2 (chưa qua hộp số, vì xe v1 tự áp). "Đồng bộ failsafe" dùng `CarController.syncProfile` (ghi cấu hình v1).

### R2. Điều kiện ARM

Tất cả phải đúng:

1. Trạng thái READY (failsafe đã đồng bộ, hash khớp).
2. Hồ sơ hợp lệ (V1).
3. Kênh Ga ở **vị trí nghỉ**: giá trị mixer của CH2 trong vùng ±5% quanh giá trị nghỉ (dùng lại `ReturnMotion.restPct`, xem lỗi H5-1).
4. Không ở chế độ Sửa bố cục.
5. Nếu hồ sơ đặt `armCondition` (Condition, vd `sw_arm == 1`) thì Condition đó đúng.

Thao tác: **nhấn giữ nút ARM 1 s** (có vòng tiến trình). Tuỳ chọn `autoArm` trong hồ sơ (mặc định tắt): tự ARM **một lần** sau mỗi lần kết nối, khi đủ điều kiện. DISARM rồi (tự động hay do người dùng) thì phải giữ nút ARM lại.

### R3. DISARM

Tự DISARM khi: mất kết nối hoặc mất tín hiệu (không có telemetry quá 1 s), telemetry báo xe đang failsafe, app xuống nền, vào Sửa bố cục, mở Cấu hình, thoát màn Lái, `armCondition` chuyển sai. Người dùng bấm nút DISARM thì DISARM ngay (không cần giữ).

Sau DISARM: về READY, reset hysteresis và khoá an toàn, phải thoả lại R2 mới ARM được.

---

## 6. Nhóm V — Kiểm tra dữ liệu (thay E7 mục Gán kênh / Mix)

| Đối tượng | Luật | Mức |
|---|---|---|
| Input | `id` đúng mẫu, không trùng; `name` 1–24 ký tự | Lỗi |
| Input | Kiểu phần tử khớp `type` (I2) | Lỗi |
| Condition | `input` tồn tại; `hyst` chỉ với so sánh lớn/nhỏ; sâu ≤ 4; ≤ 8 `cmp`; `ref` không vòng | Lỗi |
| Luật | `source` tồn tại; `destCh` 1..10; `minPct < maxPct`; các giá trị trong khoảng M1 | Lỗi |
| Luật | Priority ≥ 8 mà bật khoá an toàn | Lỗi |
| Luật | Ghi vào kênh đang tắt | Cảnh báo |
| Hồ sơ | Có ít nhất một luật đang bật ghi vào CH1 và một vào CH2 | Lỗi |
| Bố cục | Input nguồn của các luật ghi CH1/CH2 phải có phần tử trên bố cục (thay H5 "phần tử cho Ga và Lái") | Lỗi |
| Bố cục | Input được luật dùng nhưng không có phần tử trên bố cục | Cảnh báo |

Lỗi thì khoá nút Lưu; cảnh báo thì hiện vàng, vẫn lưu được.

---

## 7. Nhóm U — Giao diện

### U1. Tab trong màn Cấu hình

**Ga · Lái · Input · Mix · Kênh · Chung** (thêm tab Input; tab Kênh chỉ còn phần đầu ra).

### U2. Tab "Input"

- Danh sách: `tên · id · kiểu · phần tử đang gắn (trên bố cục đang dùng) · số luật dùng`.
- Thêm / sửa / xoá. Trang sửa có: tên, id (khoá sau khi đã có luật dùng), kiểu, bipolar/unipolar, mức bật/tắt/giữa, giá trị hằng số.
- Thanh "giá trị hiện tại" chạy trực tiếp khi đang ở màn Lái hoặc bảng xem trước.

### U3. Tab "Mix"

- Danh sách **nhóm theo kênh đích** (CH1 … CH10), trong nhóm xếp theo priority rồi thứ tự; kéo để đổi thứ tự trong nhóm.
- Mỗi thẻ: mô tả tự sinh (M6), công tắc bật/tắt, chấm `accent` khi luật đang active (lúc lái hoặc xem trước), nhãn *Chờ về giữa* khi đang chờ.
- Cuối danh sách: *"14/64 luật · 12 đang bật · priority cao chạy sau"*.
- Kéo chỉ đổi thứ tự giữa các luật cùng priority trong nhóm (priority vẫn quyết định trước).

### U4. Trình sửa luật

| Mục | Điều khiển |
|---|---|
| Nguồn | Chọn Input (có mục *Hằng số…*) |
| Điều kiện | Trình dựng: mỗi hàng `Input · toán tử · giá trị · (trễ)`; nhóm hàng bằng **Tất cả (AND)** / **Một trong (OR)**; nút **Phủ định**; chọn Condition đặt tên |
| Weight / Offset | −/+ và ô nhập; nút *Toàn dải* (unipolar: 200 / −100) |
| Curve | Tuyến tính / Expo / 5 điểm, có đồ thị nhỏ |
| Min / Max | Thanh 2 đầu |
| Đích | CH1–CH10 (hiện tên kênh) |
| Gộp / Ưu tiên | `replace · add · multiply · max · min`; priority 0–9 |
| Khoá an toàn | Bật/tắt, vùng chết |
| Xem trước | Thanh kéo cho nguồn, nút giả lập cho mọi Input dùng trong Condition, cột kết quả cho **mọi kênh bị ảnh hưởng** (chạy cùng `MixerEngine`) |

### U5. Gắn nhanh trên bảng thuộc tính (thay "Gán kênh" ở H3)

Để người dùng không phải biết về mixer mới lái được:

- Mục **Input** trong bảng thuộc tính: *Chưa gắn* · các Input cùng kiểu · **Tạo Input mới**.
- Mục **Gửi tới kênh** (lối tắt): chọn CHn thì app tạo (hoặc sửa) **một luật mặc định** `Input → CHn, weight 100, replace, priority 0, không điều kiện`. Nếu Input đã có nhiều luật hoặc luật có điều kiện thì mục này hiện *"Dùng tab Mix"* và mở thẳng tab Mix.
- Mẫu hồ sơ (E3) và bố cục mẫu (H4) được dựng sẵn bằng Input + luật mặc định, nên người mới dùng thấy giống Sprint 3.

### U6. Màn Lái

- Nút ARM / DISARM ở thanh trên, huy hiệu trạng thái R1.
- Chấm mix (G7): phần tử có Input đang tác động qua luật có điều kiện hoặc nhiều đích thì có chấm `accent`; nhấn giữ để xem danh sách luật và kênh đích.
- Ô **Kênh đầu ra** (loại ô đồng hồ mới `channelMonitor`): 10 thanh nhỏ hiện % của CH1–CH10 sau mixer.

---

## 8. Nhóm J — Dữ liệu hồ sơ (schemaVersion 2)

### J1. Cấu trúc

```
CarProfile (schemaVersion 2)
├── id, name, icon, connType, wifi, ble, updatedAt, lastSynced*, lastConnectedAt
├── inputs[]          InputDef          (I1)
├── conditions[]      ConditionDef      (K3)
├── mixer[]           MixRule           (M1)
├── channels[10]      ChannelConfig     (O1)
├── gears             GearConfig
├── failsafeTimeoutMs
├── arm               { autoArm, armCondition? }
├── output            { protocol: "rc_v2", periodMs: 25 }
├── ping              PingConfig
├── layouts[]         ControlLayout — item.inputId / inputIdY
└── activeLayoutId
```

### J2. Ví dụ đầy đủ (trường hợp A / Slider X)

```json
{
  "schemaVersion": 2,
  "id": "3f1c…",
  "name": "CAR_01",
  "connType": "wifi",
  "wifi": { "ip": "192.168.4.1", "port": 4210 },
  "inputs": [
    { "id": "steer",    "name": "Lái",     "type": "axis",   "range": "bipolar" },
    { "id": "throttle", "name": "Ga",      "type": "axis",   "range": "bipolar" },
    { "id": "slider_x", "name": "Slider X","type": "axis",   "range": "bipolar" },
    { "id": "btn_a",    "name": "Nút A",   "type": "binary", "levels": { "offPct": -100, "onPct": 100 } }
  ],
  "conditions": [],
  "mixer": [
    { "id": "r_steer", "source": "steer",    "destCh": 1, "combine": "replace" },
    { "id": "r_thr",   "source": "throttle", "destCh": 2, "combine": "replace" },
    { "id": "r_ch1", "source": "slider_x", "destCh": 1, "combine": "replace", "priority": 1,
      "condition": { "op": "cmp", "input": "btn_a", "cmp": "==", "value": 1 },
      "safety": { "requireNeutral": true, "deadzonePct": 5 } },
    { "id": "r_ch8", "source": "slider_x", "destCh": 8, "combine": "replace",
      "condition": { "op": "cmp", "input": "btn_a", "cmp": "==", "value": 0 },
      "safety": { "requireNeutral": true, "deadzonePct": 5 } }
  ],
  "channels": [
    { "index": 1, "name": "Lái", "minUs": 1100, "centerUs": 1500, "maxUs": 1900, "failsafeUs": 1500, "enabled": true },
    { "index": 2, "name": "Ga",  "minUs": 1000, "centerUs": 1500, "maxUs": 2000, "failsafeUs": 1500, "enabled": true },
    { "index": 8, "name": "Phụ", "minUs": 1100, "centerUs": 1500, "maxUs": 1900, "failsafeUs": 1500, "enabled": true }
  ],
  "failsafeTimeoutMs": 400,
  "arm": { "autoArm": false },
  "output": { "protocol": "rc_v2", "periodMs": 25 },
  "layouts": [
    { "id": "l1", "name": "Mặc định", "cols": 24, "rows": 12, "items": [
      { "id": "i1", "kind": "stickV", "inputId": "throttle", "x": 1,  "y": 2, "w": 3, "h": 9 },
      { "id": "i2", "kind": "stickH", "inputId": "steer",    "x": 15, "y": 7, "w": 8, "h": 3 },
      { "id": "i3", "kind": "knob",   "inputId": "slider_x", "x": 10, "y": 7, "w": 4, "h": 4 },
      { "id": "i4", "kind": "toggle", "inputId": "btn_a",    "x": 10, "y": 3, "w": 3, "h": 2 }
    ] }
  ],
  "activeLayoutId": "l1"
}
```

Trường vắng mặt nhận giá trị mặc định ở M1 / I1 / O1; `channels` khi lưu luôn ghi đủ 10 phần tử (ví dụ rút gọn). Ở ví dụ này CH1 do `r_steer` điều khiển; khi A = 1, `r_ch1` (priority 1, `replace`) đè lên và Slider X điều khiển CH1.

### J3. JSON Schema

File `app/assets/schema/profile.v2.schema.json` (JSON Schema draft 2020-12) mô tả J1 với đủ khoảng giá trị ở I1, K1, M1, O1. Dùng để:

- Kiểm tra file khi **nhập** hồ sơ (E8), trước bước V.
- Test: mọi hồ sơ mẫu và kết quả chuyển đổi (J4) phải qua schema.

### J4. Chuyển hồ sơ Sprint 3 (v1 → v2)

Chạy trong `profile_migration.dart` khi đọc file có `schemaVersion` < 2 (v0 → v1 → v2); file gốc được sao lưu thành `profiles/<id>.v1.bak` (không đuôi `.json` để không bị đọc lại như một hồ sơ), rồi ghi bản đã chuyển.

| Sprint 3 | Sprint 4 |
|---|---|
| Kênh N được gán vào phần tử (trên bất kỳ bố cục nào) | Input `ch{N}` (tên = tên kênh, kiểu theo phần tử đầu tiên tìm thấy) + luật `ch{N} → CHN, replace, priority 0` |
| `channels[N].offValuePct` | `inputs["ch{N}"].levels.offPct` |
| `item.channel` / `item.channelY` | `item.inputId` / `item.inputIdY` = `ch{N}` |
| Hai bố cục gán kênh N vào hai **kiểu** phần tử khác nhau (vd nút và núm) | Input thứ hai `ch{N}_2` cho kiểu sau; phần tử đó gắn vào `ch{N}_2`, **không** tạo luật; ghi cảnh báo |
| Luật linear | `source = ch{src}`, `weight = gainPct`, `offset = offsetPct`, `combine`: override→replace, add→add, max→max; `priority 1`; thứ tự giữ nguyên |
| Luật curve | Như linear, `curve = points(curvePts)` |
| `gateCh` | `condition = ch{gate} > 0` |
| Luật threshold | Hai luật hằng số cùng đích, `priority 1`: `onValue` khi `ch{src} >= onAt, hyst = onAt − offBelow`, `offValue` khi `not (…)` cùng biểu thức. Hai biểu thức cùng đầu vào nên trạng thái trễ luôn trùng nhau, không cần Condition đặt tên |
| Hằng số trong luật threshold / kênh không có phần tử | Input hằng số `k_{giá trị}` (vd `k_100`, `k_m40`); kênh nguồn không có phần tử đọc `k_0` như Sprint 3 đọc 0% |
| Luật `max` ghi vào kênh không có phần tử | Thêm luật gốc `k_0 → CHn` (priority 0) để so với 0% như Sprint 3 |
| Luật mix Sprint 3 (không phải select) | `safety.requireNeutral = false` (Sprint 3 không có khoá an toàn ở các loại này) |
| Luật đang bật ghi vào kênh đang tắt | Bật kênh (Sprint 3 vẫn xuất giá trị mix; Sprint 4 kênh tắt ra failsafe) |
| Luật select | Hai luật: nguồn → `targetOnCh` khi `ch{select} > 0`; nguồn → `targetOffCh` khi `not`; `safety` lấy từ `requireNeutralToSwitch`, `neutralDeadzonePct` |
| Luật lấy nguồn là kênh **đã bị luật khác ghi** (chuỗi CH1→CH3→CH5) | Dùng Input của kênh nguồn (giá trị **trước** mix); ghi cảnh báo "kết quả có thể khác" |
| Kênh bật nhưng không có phần tử và không bị luật ghi | Không tạo luật (ra Center như cũ) |

- Sau khi chuyển: chạy V; lỗi thì vẫn mở được hồ sơ nhưng hiện danh sách lỗi và khoá lái tới khi sửa.
- Có **báo cáo chuyển đổi** (hộp thoại một lần, liệt kê các cảnh báo ở trên).
- Mọi dòng trong bảng trên có test (N4).

---

## 9. Nhóm P — Mã nguồn

### P1. File mới và file đổi

| File | Việc |
|---|---|
| `models/input_def.dart` | Mới: `InputDef`, `InputLevels`, enum `InputType`, `AxisRange` |
| `models/condition.dart` | Mới: cây `Expr`, `ConditionDef`, (de)serialize, kiểm tra |
| `models/mixer_rule.dart` | Mới: `MixRule`, `MixCurve`, `SwitchSafety`, `Combine`, `validateMixer` (M1, V). `models/mix_rule.dart` cũ bị xoá |
| `models/channel_config.dart` | Bỏ `offValuePct` |
| `models/control_layout.dart` | `channel/channelY` → `inputId/inputIdY`; `assignChannel` → `bindInput` |
| `models/car_profile.dart` | Thêm `inputs`, `conditions`, `arm`, `output`; `mixes` → `mixer`; `schemaVersion = 2` |
| `data/profile_migration.dart` | Thêm bước v1 → v2 (J4) |
| `services/input_manager.dart` | Mới: đọc giá trị phần tử → trạng thái + % của từng Input |
| `services/condition_engine.dart` | Mới: biên dịch `Expr` thành chương trình phẳng, giữ trạng thái hysteresis |
| `services/mixer_engine.dart` | Mới: `MixerEngine` theo M2–M4. `services/mix_engine.dart` cũ bị xoá |
| `services/output_pipeline.dart` | Input → Condition → Mixer → Channel Stage (O2) → ARM gate |
| `services/arm_controller.dart` | Mới: máy trạng thái R1–R3 |
| `protocol/output_protocol.dart` | Mới: interface O4 + `RcV2Udp`, `RcV2Ble`, `RcV1Legacy` — **làm cùng C1–C2** (chưa làm) |
| `controller/car_controller.dart` | Đã: bỏ `values` / `holdNeutral`, dùng `OutputPipeline` + `ArmController`, vị trí theo mã Input. Còn lại khi có C1: bỏ `syncProfile`, dùng `OutputProtocol` |
| `data/profile_repository.dart` | Tự chuyển hồ sơ cũ lúc mở app, giữ bản `.bak`, `migrationReports` cho báo cáo |
| `screens/settings_screen.dart` | 6 tab (U1): thêm Input, Mix nhóm theo kênh, mục ARM trong Chung |
| `screens/garage_screen.dart` | Hộp thoại báo cáo chuyển đổi (J4) |
| `test/support/sprint3_reference.dart`, `test/fixtures/sprint3_profile.json` | Bản đóng băng thuật toán Sprint 3 + hồ sơ Sprint 3 thật cho N4 |
| `screens/input_screen.dart`, `widgets/condition_builder.dart` | Mới (U2, U4) |
| `screens/mix_rule_screen.dart`, `widgets/mix_rule_card.dart`, `widgets/mix_preview.dart` | Viết lại (U3, U4) |
| `layout/properties_panel.dart`, `layout/layout_templates.dart` | U5; mẫu dựng bằng Input + luật |
| `screens/channel_detail_screen.dart`, `widgets/channel_tile.dart` | Bỏ phần gán phần tử; hiện "các luật ghi vào kênh này" |
| `screens/control_screen.dart` | ARM/DISARM, chấm mix, ô `channelMonitor` |

`fake_car.py` và firmware **không đổi** ngoài những gì C1–C4 đã đặc tả.

### P2. Giao diện chính

```dart
class InputManager {
  void setFromItem(String inputId, double pct);       // từ widget, % vị trí cần
  void resetToRest();
  List<double> get state;                             // trạng thái cho Condition (I2)
  List<double> get value;                             // % cho mixer (I2)
}

class MixerEngine {
  MixerEngine(CarProfile p);                          // biên dịch Condition, sắp luật
  List<double> run(InputManager inputs);              // 10 kênh %, không cấp phát
  Set<String> get activeRuleIds;                      // cho U3/U6
  Set<String> get pendingRuleIds;                     // đang "chờ về giữa"
  void reset();                                       // hysteresis + latch
}

class OutputPipeline {
  List<int> run({required int gear, required ArmState arm});   // 10 kênh µs
}
```

---

## 10. Nhóm N — Kiểm thử

| Mã | Nội dung |
|---|---|
| N1 | Unit test `ConditionEngine`: 6 toán tử trên 4 kiểu Input; AND/OR/NOT lồng 4 tầng; hysteresis (bảng G2a, dao động trong vùng giữ, reset khi DISARM); `ref` dùng chung trạng thái; phát hiện `ref` vòng |
| N2 | Unit test `MixerEngine`: bảng M3 cho 5 kiểu `combine`; priority; kênh không có luật = 0%; bảng M4 (A / Slider X) từng bước; luật priority 9 tác động ngay dù nguồn lệch tâm; unipolar + *Toàn dải* |
| N3 | Vector test `tests/mix_vectors.json` (đầu vào theo thời gian → 10 kênh µs mong đợi), chạy qua cả `OutputPipeline` |
| N4 | Migration: mỗi dòng bảng J4 một ca; hồ sơ Sprint 3 thật trong `app/test/fixtures/` chuyển xong qua J3 và V; **so kết quả µs** Sprint 3 và Sprint 4 trên cùng chuỗi đầu vào (khác nhau chỉ được phép ở ca có cảnh báo) |
| N5 | `ArmController`: mọi cạnh của R1; không ARM được khi ga lệch nghỉ, khi đang sửa bố cục, khi `armCondition` sai; tự DISARM khi app xuống nền |
| N6 | Hiệu năng: 64 luật + 32 Condition + 48 Input, 10 000 chu kỳ, p99 ≤ 2 ms (đã chạy trên PC; còn đo trên máy Android thật); không cấp phát trong vòng |
| N7 | Tích hợp với `fake_car.py`: READY gửi `failsafeUs`; ARM rồi gạt A khi Slider X = 70% → `fake_car.py` in CH1 giữ 70% tới khi về giữa |

---

## 11. Tiêu chí nghiệm thu

- [ ] Tạo Input *Slider X* (núm) và *Nút A* (bật/tắt), các luật như J2: A bật thì `fake_car.py` in CH1 theo núm, CH8 = Center; A tắt thì CH8 theo núm, CH1 trở lại theo cần lái.
- [ ] Gạt A khi núm ở 70%: kênh cũ giữ 70% cho tới khi núm về ≤ 5%, rồi mới chuyển; không có chu kỳ nào kênh mới nhận 70% đột ngột.
- [ ] Luật khẩn cấp `btn_stop == 1 → CH2 = 0%, priority 9` đè ga ngay cả khi đang ga hết cỡ.
- [ ] Condition `steer >= 80, hyst 10 → CH3 = 100%` chạy đúng bảng G2a.
- [ ] Vừa kết nối: `fake_car.py` nhận `failsafeUs`, xe không chạy cho tới khi giữ nút ARM 1 s; đang giữ cần ga thì không ARM được.
- [ ] App xuống nền khi đang ARMED: tự DISARM, xe nhận `failsafeUs`.
- [ ] Mở hồ sơ Sprint 3 (có đèn, còi, luật select và threshold): tự chuyển, có báo cáo, lái ra **cùng µs** như Sprint 3 với cùng thao tác.
- [ ] Đổi sang bố cục khác dùng chung Input: mix vẫn đúng, không phải cấu hình lại.
- [ ] Nhập file hồ sơ sai schema: báo lỗi rõ trường nào sai, không ghi đè hồ sơ đang có.
- [ ] 64 luật chạy ≤ 2 ms một chu kỳ trên Android tầm trung.

---

## 12. Thứ tự thực hiện

```
I1 → K1 → M1 → J1                (mô hình + JSON, test serialize)
→ J4 (migration) + N4             (làm sớm để khoá hành vi Sprint 3 bằng test)
→ K2 → K3 → N1                    (ConditionEngine)
→ M2 → M3 → M4 → M5 → N2 → N3     (MixerEngine)
→ O1 → O2 → O4                    (Channel Stage, Protocol Engine — cùng việc thay syncProfile bằng FS_WRITE)
→ R1 → R2 → R3 → N5               (ARM)
→ V → J3
→ U5 → U2 → U3 → U4 → U1 → U6     (giao diện; U5 trước để bố cục mẫu chạy được sớm)
→ N6 → N7 → nghiệm thu
```

Làm song song với các mục Sprint 4 còn lại trong `dac_ta_sprint_3.md` (C1–C4, E5–E6, F5–F9…). G3, G4, G7–G10 của Sprint 3 được thay bằng M, V, U6, N ở đây.

---

## 13. Việc cần chốt

| # | Câu hỏi | Đề xuất | Ảnh hưởng |
|---|---|---|---|
| 1 | Mặc định ARM: giữ nút 1 s hay tự ARM? | Giữ nút 1 s, `autoArm` tắt | R2, U6 |
| 2 | READY gửi `failsafeUs` hay Center? | `failsafeUs` (cùng hành vi với lúc mất sóng) | R1 |
| 3 | Kênh Ga/Lái cố định CH2/CH1 hay chọn được? | Cố định trong Sprint 4 | O1, R2, H5 |
| 4 | Giới hạn 64 luật / 32 Condition / 48 Input có đủ? | Đủ cho xe và cho hồ sơ Sprint 3 chuyển sang | M1, M5 |
| 5 | Có giữ nút *Toàn dải* hay đổi mặc định unipolar thành Min…Max? | Giữ nút; mặc định unipolar 0…100 → Center…Max | I2, M4 |
