import 'package:flutter/material.dart';

import '../../core/models/peer_device.dart';

/// 设备条：最左边固定一个「搜索」按钮，后面是在线/已知设备。
///
/// 设备发现不再常驻轮询，所以即使一个设备都没有，这一条也要显示——
/// 否则用户找不到重新搜索的入口。
class DeviceBar extends StatelessWidget {
  const DeviceBar({
    super.key,
    required this.peers,
    required this.activeId,
    required this.onSelect,
    required this.onSearch,
    required this.scanning,
  });

  final List<PeerDevice> peers;
  final String? activeId;
  final ValueChanged<String> onSelect;
  final VoidCallback onSearch;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: peers.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _SearchChip(scanning: scanning, onTap: onSearch);
          }
          final peer = peers[index - 1];
          return _Chip(
            label: peer.alias,
            icon: peer.platform == 'web'
                ? Icons.desktop_windows_rounded
                : peer.isIos
                    ? Icons.phone_iphone_rounded
                    : Icons.phone_android_rounded,
            active: peer.id == activeId,
            online: peer.isOnline,
            onTap: () => onSelect(peer.id),
          );
        },
      ),
    );
  }
}

class _SearchChip extends StatelessWidget {
  const _SearchChip({required this.scanning, required this.onTap});

  final bool scanning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: scanning ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withOpacity(0.9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: scanning
                      ? scheme.primary.withOpacity(0.55)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: scanning
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          scheme.primary,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.radar_rounded,
                      size: 24,
                      color: scheme.onSurfaceVariant,
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              scanning ? '搜索中' : '搜索',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: scanning ? FontWeight.w600 : FontWeight.w400,
                color: scanning ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.active,
    required this.online,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avatarColor = active
        ? scheme.primary
        : scheme.surfaceContainerHighest.withOpacity(0.9);
    final iconColor = active ? scheme.onPrimary : scheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: avatarColor,
                    shape: BoxShape.circle,
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: scheme.primary.withOpacity(0.28),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(icon, size: 24, color: iconColor),
                ),
                if (!online)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surface.withOpacity(0.55),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: online ? const Color(0xFF2ECC71) : scheme.outline,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
