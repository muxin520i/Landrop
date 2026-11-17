import 'dart:convert';
import 'dart:io';

/// 当前版本号。发版时与 pubspec.yaml 的 `version:` 保持一致。
const String kAppVersion = '1.0.6';

/// 仓库信息，用于检查更新与跳转下载页。
const String kRepoOwner = 'muxin520i';
const String kRepoName = 'Landrop';

/// 最新版本的发布页（GitHub Releases 永远指向最后一个 release）。
const String kReleasePage =
    'https://github.com/$kRepoOwner/$kRepoName/releases/latest';

/// 一次检查更新的结果。
class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    this.notes = '',
    this.publishedAt,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;

  /// Release 说明，纯文本展示。
  final String notes;

  final DateTime? publishedAt;

  bool get hasUpdate => compareVersions(latestVersion, currentVersion) > 0;
}

/// 比较两个版本号，a > b 返回正数，相等返回 0。
/// 只看前三段数字，忽略 `v` 前缀和 `+build` 后缀。
int compareVersions(String a, String b) {
  final pa = _segments(a);
  final pb = _segments(b);
  for (var i = 0; i < 3; i++) {
    final diff = pa[i] - pb[i];
    if (diff != 0) return diff;
  }
  return 0;
}

List<int> _segments(String version) {
  final clean = version.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
  final parts = clean.split('.');
  return List<int>.generate(3, (i) {
    if (i >= parts.length) return 0;
    final digits = parts[i].replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  });
}

/// 去 GitHub 查最新 release。不依赖任何账号，也不需要 token。
///
/// 两条路并行：API（能拿到更新说明）+ 发布页 302 跳转（不受 API 限流影响）。
/// 谁先拿到用谁，都失败才返回 null。
class UpdateChecker {
  const UpdateChecker();

  static const String _api =
      'https://api.github.com/repos/$kRepoOwner/$kRepoName/releases/latest';

  /// 查不到（离线、超时、限流、被墙）时返回 null，调用方按「稍后重试」处理。
  Future<UpdateInfo?> fetchLatest({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final results = await Future.wait<UpdateInfo?>([
      _fromApi(timeout),
      _fromReleaseRedirect(timeout),
    ]);
    for (final info in results) {
      if (info != null) return info;
    }
    return null;
  }

  Future<UpdateInfo?> _fromApi(Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(_api)).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Landrop/$kAppVersion');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      final json = jsonDecode(body);
      if (json is! Map) return null;

      final tag = (json['tag_name'] as String? ?? '').trim();
      if (tag.isEmpty) return null;

      final url = (json['html_url'] as String? ?? '').trim();
      return UpdateInfo(
        currentVersion: kAppVersion,
        latestVersion: tag.replaceFirst(RegExp(r'^[vV]'), ''),
        releaseUrl: url.isEmpty ? kReleasePage : url,
        notes: (json['body'] as String? ?? '').trim(),
        publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// `releases/latest` 会 302 到 `/releases/tag/vX.Y.Z`，从 Location 里读版本号。
  /// 不读 JSON、不占 API 额度，是限流或 API 不通时的兜底。
  Future<UpdateInfo?> _fromReleaseRedirect(Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(kReleasePage)).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Landrop/$kAppVersion)',
      );
      final response = await request.close().timeout(timeout);
      final location = response.headers.value(HttpHeaders.locationHeader) ?? '';
      await response.drain<void>();

      final match = RegExp(r'/releases/tag/([^/?#]+)').firstMatch(location);
      if (match == null) return null;
      final tag = Uri.decodeComponent(match.group(1)!);

      return UpdateInfo(
        currentVersion: kAppVersion,
        latestVersion: tag.replaceFirst(RegExp(r'^[vV]'), ''),
        releaseUrl: 'https://github.com/$kRepoOwner/$kRepoName/releases/tag/$tag',
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
