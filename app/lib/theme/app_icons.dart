// Gom icon về một chỗ: Heroicons v2 + 4 icon tự vẽ (Heroicons không có).
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:heroicons/heroicons.dart';

export 'package:heroicons/heroicons.dart' show HeroIcons, HeroIconStyle;

abstract final class AppIcons {
  static const wifi = HeroIcons.wifi;
  static const connect = HeroIcons.link;
  static const disconnect = HeroIcons.linkSlash;
  static const scan = HeroIcons.magnifyingGlass;
  static const config = HeroIcons.adjustmentsHorizontal;
  static const settings = HeroIcons.cog6Tooth;
  static const back = HeroIcons.arrowLeft;
  static const batteryHalf = HeroIcons.battery50;
  static const batteryFull = HeroIcons.battery100;
  static const batteryEmpty = HeroIcons.battery0;
  static const current = HeroIcons.bolt;
  static const signal = HeroIcons.signal;
  static const signalOff = HeroIcons.signalSlash;
  static const save = HeroIcons.arrowDownTray;
  static const syncFailsafe = HeroIcons.arrowUpTray;
  static const reset = HeroIcons.arrowUturnLeft;
  static const plus = HeroIcons.plus;
  static const minus = HeroIcons.minus;
  static const success = HeroIcons.checkCircle;
  static const warning = HeroIcons.exclamationTriangle;
  static const light = HeroIcons.lightBulb;
  static const horn = HeroIcons.megaphone;
  static const mix = HeroIcons.arrowsRightLeft;
  static const drag = HeroIcons.bars3;
  static const delete = HeroIcons.trash;
  static const duplicate = HeroIcons.documentDuplicate;
  static const exportFile = HeroIcons.arrowUpOnSquare;
  static const importFile = HeroIcons.arrowDownOnSquare;
  static const diagnostics = HeroIcons.chartBar;
  static const findCar = HeroIcons.bellAlert;
  static const themeLight = HeroIcons.sun;
  static const themeDark = HeroIcons.moon;
  static const themeSystem = HeroIcons.computerDesktop;
  static const edit = HeroIcons.pencilSquare;
  static const more = HeroIcons.ellipsisVertical;
  static const locked = HeroIcons.lockClosed;
  static const unlocked = HeroIcons.lockOpen;
  static const close = HeroIcons.xMark;
  static const undo = HeroIcons.arrowUturnLeft;
  static const redo = HeroIcons.arrowUturnRight;
  static const addControl = HeroIcons.squaresPlus;

  /// Icon cho nút/công tắc, chọn được trong bảng thuộc tính (H3)
  static const pickable = <String, HeroIcons>{
    'light-bulb': HeroIcons.lightBulb,
    'megaphone': HeroIcons.megaphone,
    'bolt': HeroIcons.bolt,
    'fire': HeroIcons.fire,
    'star': HeroIcons.star,
    'flag': HeroIcons.flag,
    'bell-alert': HeroIcons.bellAlert,
    'play': HeroIcons.play,
    'arrow-path': HeroIcons.arrowPath,
    'home': HeroIcons.home,
    'truck': HeroIcons.truck,
  };
}

/// Icon Heroicons: mặc định Outline 24; `solid` khi đang bật/chọn; `mini` cho nút nhỏ.
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size, this.color, this.solid = false, this.mini = false});

  final HeroIcons icon;
  final double? size;
  final Color? color;
  final bool solid, mini;

  @override
  Widget build(BuildContext context) => HeroIcon(
        icon,
        size: size ?? (mini ? 20 : null),
        color: color,
        style: mini
            ? HeroIconStyle.mini
            : (solid ? HeroIconStyle.solid : HeroIconStyle.outline),
      );
}

/// 4 icon Heroicons không có, vẽ theo cùng quy cách (24×24, nét 1.5, đầu tròn)
enum CustomIcon {
  bluetooth('assets/icons/bluetooth.svg'),
  car('assets/icons/car.svg'),
  speedometer('assets/icons/speedometer.svg'),
  steering('assets/icons/steering.svg');

  const CustomIcon(this.asset);
  final String asset;
}

class CustomIconView extends StatelessWidget {
  const CustomIconView(this.icon, {super.key, this.size, this.color});

  final CustomIcon icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = size ?? IconTheme.of(context).size ?? 24;
    return SvgPicture.asset(
      icon.asset,
      width: s,
      height: s,
      colorFilter: ColorFilter.mode(
        color ?? IconTheme.of(context).color ?? Colors.black,
        BlendMode.srcIn,
      ),
    );
  }
}
