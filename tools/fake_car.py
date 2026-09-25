"""Xe RC giả lập qua UDP — dùng để test app khi không có phần cứng ESP32.

Nói đúng giao thức trong app/lib/protocol/protocol.dart và firmware/src/protocol.h:
  khung = [0xAA, type, len, payload..., crc8(type..payload)]

Cần cài:  pip install -r tools/requirements.txt   (chỉ cần gói "rich")
Chạy:     python tools/fake_car.py
Trong app điền IP:
  - Android emulator : 10.0.2.2   (10.0.2.2 = máy tính chủ, nhìn từ trong emulator)
  - Điện thoại thật  : IP LAN của máy tính, cùng WiFi
  Port giữ nguyên 4210.
"""

import math
import socket
import struct
import sys
import threading
import time

from rich.console import Console
from rich.live import Live
from rich.panel import Panel
from rich.table import Table

HOST, PORT = "0.0.0.0", 4210
HEADER = 0xAA

# Loại gói
CONTROL, TELEMETRY = 0x01, 0x02
CONFIG_GET, CONFIG_DATA, CONFIG_SET, CONFIG_SAVE, CONFIG_RESET = 0x10, 0x11, 0x12, 0x13, 0x14
ACK = 0x20
PING, PONG = 0x30, 0x31  # ping (F1): PING seq:u16 t_send:u32 -> PONG seq:u16 t_send:u32 uptime:u32

FLAG_FAILSAFE, FLAG_ARMED = 0x01, 0x02
FAILSAFE_AFTER = 0.4  # giây không nhận lệnh thì vào failsafe, khớp failsafeTimeoutMs mặc định


def lan_ips() -> list:
    """IP LAN của máy này — cái đầu tiên là địa chỉ dùng để ra mạng."""
    ips = []
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))       # không gửi gói nào, chỉ để hỏi route
        ips.append(s.getsockname()[0])
    except OSError:
        pass
    finally:
        s.close()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except OSError:
        pass
    return ips


def crc8(data: bytes) -> int:
    """CRC-8 poly 0x07, init 0 — giống hàm crc8() trong protocol.dart."""
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = ((crc << 1) ^ 0x07) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc


def encode(ptype: int, payload: bytes = b"") -> bytes:
    body = bytes([ptype, len(payload)]) + payload
    return bytes([HEADER]) + body + bytes([crc8(body)])


def decode(buf: bytes):
    """Trả (type, payload) hoặc None nếu khung hỏng."""
    if len(buf) < 4 or buf[0] != HEADER:
        return None
    length = buf[2]
    if len(buf) != length + 4:
        return None
    body = buf[1:3 + length]
    if crc8(body) != buf[3 + length]:
        return None
    return buf[1], buf[3:3 + length]


def default_config() -> dict:
    """Giá trị mặc định lấy từ firmware/src/servo_logic.h::setDefaults()."""
    return {
        # min, center, max, trim, offset, reverse, failsafe
        "throttle": [1000, 1500, 2000, 0, 0, 0, 1500],
        "steering": [1100, 1500, 1900, 0, 0, 0, 1500],
        "failsafe_timeout_ms": 400,
        "gear_count": 3,
        "gear_limit": [30, 60, 100, 100, 100],
    }


# ChannelConfig = 13 byte: u16 min, u16 center, u16 max, i16 trim, i16 offset, u8 reverse, u16 failsafe
CH = struct.Struct("<HHHhhBH")


def pack_config(c: dict) -> bytes:
    out = CH.pack(*c["throttle"]) + CH.pack(*c["steering"])
    out += struct.pack("<HB", c["failsafe_timeout_ms"], c["gear_count"])
    out += bytes(c["gear_limit"])
    assert len(out) == 34, len(out)
    return out


def unpack_config(p: bytes) -> dict:
    if len(p) != 34:
        raise ValueError("cấu hình phải đúng 34 byte")
    return {
        "throttle": list(CH.unpack_from(p, 0)),
        "steering": list(CH.unpack_from(p, 13)),
        "failsafe_timeout_ms": struct.unpack_from("<H", p, 26)[0],
        "gear_count": p[28],
        "gear_limit": list(p[29:34]),
    }


def describe_config(c: dict) -> str:
    """Tóm tắt cấu hình thành một dòng để in ra."""
    def ch(name, v):
        mn, ce, mx, tr, of, rv, fs = v
        return f"{name} {mn}/{ce}/{mx} trim{tr:+d} offset{of:+d}{' đảo' if rv else ''} fs{fs}"
    return (f"{ch('ga', c['throttle'])} | {ch('lái', c['steering'])}"
            f" | timeout {c['failsafe_timeout_ms']}ms"
            f" | {c['gear_count']} số {c['gear_limit'][:c['gear_count']]}")


def valid_channel(ch) -> bool:
    mn, ce, mx, tr, of, rv, fs = ch
    return (800 <= mn and mx <= 2200 and mn < ce < mx
            and abs(tr) <= 200 and abs(of) <= 300 and mn <= fs <= mx and rv <= 1)


def valid_config(c: dict) -> bool:
    if not (valid_channel(c["throttle"]) and valid_channel(c["steering"])):
        return False
    if not 100 <= c["failsafe_timeout_ms"] <= 3000:
        return False
    if not 1 <= c["gear_count"] <= 5:
        return False
    return all(1 <= c["gear_limit"][i] <= 100 for i in range(c["gear_count"]))


class FakeCar:
    def __init__(self, console: Console):
        self.console = console
        self.live: Live | None = None   # gán sau khi main() mở khung Live
        self.cfg = default_config()
        self.saved = pack_config(self.cfg)
        self.throttle = 0      # -1000..1000
        self.steering = 0
        self.gear = 1
        self.last_seq = 0
        self.last_cmd_at = 0.0
        self.speed_cms = 0.0
        self.tele = None       # telemetry vừa gửi, để hiển thị
        self.client = None
        self.started = time.monotonic()
        self.lock = threading.Lock()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((HOST, PORT))

    # ---------- hiển thị ----------
    def log(self, msg: str, style: str = ""):
        """In một dòng sự kiện phía trên khung trạng thái (rich tự chèn đúng chỗ)."""
        self.console.print(msg, style=style or None)

    def refresh(self):
        if self.live is not None:
            self.live.update(self.render_status())

    def render_status(self) -> Panel:
        """Khung trạng thái sống: trái là lệnh app gửi xuống, phải là telemetry xe gửi lên."""
        if self.client is None:
            return Panel("chờ app kết nối…", title="Xe giả", border_style="grey50")

        limit = self.cfg["gear_limit"][max(0, min(self.gear, 5) - 1)]
        table = Table.grid(padding=(0, 3))
        table.add_column(justify="left")
        table.add_column(justify="left")
        table.add_row(
            f"[bold]Client[/]   {self.client[0]}:{self.client[1]}",
            f"[bold]Seq[/]      {self.last_seq}",
        )
        table.add_row(
            f"[bold]Ga[/]       {self.throttle:+5d}",
            f"[bold]Lái[/]      {self.steering:+5d}",
        )
        table.add_row(
            f"[bold]Số[/]       {self.gear} ({limit}% ga)",
            "",
        )

        if self.tele is None:
            return Panel(table, title="Xe giả — chờ telemetry", border_style="yellow")

        mv, ma, cms, rssi, flags = self.tele
        failsafe = bool(flags & FLAG_FAILSAFE)
        state = "FAILSAFE" if failsafe else ("ARMED" if flags & FLAG_ARMED else "IDLE")
        table.add_row(
            f"[bold]Pin[/]      {mv / 1000:.2f} V",
            f"[bold]Dòng[/]     {ma / 1000:5.2f} A",
        )
        table.add_row(
            f"[bold]Tốc độ[/]   {cms:3d} cm/s ({cms * 0.036:4.1f} km/h)",
            f"[bold]RSSI[/]     {rssi} dBm",
        )
        border = "red" if failsafe else "green"
        return Panel(table, title=f"Xe giả — {state}", border_style=border)

    def banner(self):
        self.console.print(f"[bold]Xe giả đang nghe UDP {HOST}:{PORT}[/]")
        self.console.print("  Emulator  -> điền IP 10.0.2.2")
        ips = lan_ips()
        if ips:
            self.console.print(f"  Máy thật  -> điền IP [bold]{ips[0]}[/]")
            for extra in ips[1:]:
                self.console.print(f"              (hoặc {extra})")
        else:
            self.console.print("  Máy thật  -> không dò được IP LAN, xem lệnh ipconfig / ip addr")
        self.console.print("  Ctrl+C để dừng")
        self.console.print("  cấu hình: " + describe_config(self.cfg) + "\n")

    # ---------- nhận ----------
    def serve(self):
        while True:
            data, addr = self.sock.recvfrom(512)
            frame = decode(data)
            if frame is None:
                self.log(f"  khung hỏng từ {addr}: {data.hex()}", style="red")
                continue
            ptype, payload = frame
            if ptype == PING:
                # Trả ngay về đúng địa chỉ gửi, không đổi client nhận telemetry
                # (ping nhanh từ màn "Xe của tôi" dùng socket riêng)
                if len(payload) == 6:
                    seq, t_send = struct.unpack("<HI", payload)
                    uptime = int((time.monotonic() - self.started) * 1000) & 0xFFFFFFFF
                    self.sock.sendto(encode(PONG, struct.pack("<HII", seq, t_send, uptime)), addr)
                continue
            with self.lock:
                if addr != self.client:
                    self.log(f"-> app kết nối từ {addr[0]}:{addr[1]}", style="cyan")
                self.client = addr
                self.handle(ptype, payload, addr)
            self.refresh()

    def handle(self, ptype, payload, addr):
        if ptype == CONTROL:
            if len(payload) != 6:
                return
            thr, steer, gear, seq = struct.unpack("<hhBB", payload)
            self.throttle, self.steering = thr, steer
            self.gear, self.last_seq = gear, seq
            self.last_cmd_at = time.monotonic()

        elif ptype == CONFIG_GET:
            self.sock.sendto(encode(CONFIG_DATA, pack_config(self.cfg)), addr)
            self.log(f"-> gửi cấu hình cho {addr[0]}:{addr[1]}")

        elif ptype == CONFIG_SET:
            try:
                new = unpack_config(payload)
                ok = valid_config(new)
            except ValueError:
                ok = False
            if ok:
                self.cfg = new
            self.sock.sendto(encode(ACK, bytes([CONFIG_SET, 1 if ok else 0])), addr)
            self.log(f"-> áp dụng cấu hình: {'OK' if ok else 'TỪ CHỐI'}", style="green" if ok else "red")
            if ok:
                self.log("   " + describe_config(new))

        elif ptype == CONFIG_SAVE:
            self.saved = pack_config(self.cfg)
            self.sock.sendto(encode(ACK, bytes([CONFIG_SAVE, 1])), addr)
            self.log("-> đã lưu cấu hình")

        elif ptype == CONFIG_RESET:
            self.cfg = default_config()
            self.saved = pack_config(self.cfg)
            self.sock.sendto(encode(CONFIG_DATA, pack_config(self.cfg)), addr)
            self.log("-> khôi phục mặc định")
            self.log("   " + describe_config(self.cfg))

    # ---------- gửi telemetry 10 Hz ----------
    def telemetry_loop(self):
        tick = 0
        while True:
            time.sleep(0.1)
            with self.lock:
                addr = self.client
                if addr is None:
                    continue
                idle = time.monotonic() - self.last_cmd_at
                failsafe = idle > FAILSAFE_AFTER

                # Ga hiệu dụng sau khi qua giới hạn số
                limit = self.cfg["gear_limit"][max(0, min(self.gear, 5) - 1)]
                eff = 0 if failsafe else self.throttle * limit / 100 / 1000  # -1..1

                # Tốc độ bám theo ga với quán tính nhẹ (1 km/h = 27.78 cm/s)
                target = abs(eff) * 42.0 * 27.78  # ~42 km/h khi ga hết cỡ
                self.speed_cms += (target - self.speed_cms) * 0.18
                if self.speed_cms < 0.5:
                    self.speed_cms = 0.0

                tick += 1
                battery_mv = int(8000 - 600 * min(1.0, tick / 3000) + 40 * math.sin(tick / 9))
                current_ma = int(abs(eff) * 24000 + 350 + 120 * math.sin(tick / 5))
                rssi = int(-46 - 12 * abs(math.sin(tick / 40)))
                flags = (FLAG_FAILSAFE if failsafe else 0) | (0 if failsafe else FLAG_ARMED)

                payload = struct.pack(
                    "<HhHbBBB",
                    battery_mv,
                    current_ma,
                    int(self.speed_cms),
                    rssi,
                    flags,
                    self.gear,
                    self.last_seq,
                )
                self.tele = (battery_mv, current_ma, int(self.speed_cms), rssi, flags)
                try:
                    self.sock.sendto(encode(TELEMETRY, payload), addr)
                except OSError:
                    pass
            self.refresh()


def main():
    try:   # console Windows hay là cp1252, tiếng Việt sẽ lỗi nếu ghi ra file
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    console = Console()
    car = FakeCar(console)
    car.banner()

    with Live(car.render_status(), console=console, refresh_per_second=12, transient=False) as live:
        car.live = live
        threading.Thread(target=car.telemetry_loop, daemon=True).start()
        try:
            car.serve()
        except KeyboardInterrupt:
            pass

    console.print("\nĐã dừng xe giả.")


if __name__ == "__main__":
    main()
