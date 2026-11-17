import 'package:shared_preferences/shared_preferences.dart';

/// 轻量本地设置：设备名、是否把收到的图片视频自动存进系统相册。
///
/// 用 SharedPreferences 而不是自己写文件：这两项都是布尔和短字符串，
/// 读一次就缓存，不参与首屏渲染的关键路径。
class AppSettings {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const String _kAlias = 'device_alias';
  static const String _kAutoSavePhotos = 'auto_save_photos';
  static const String _kWebAccess = 'web_access';

  String? _alias;
  bool _autoSavePhotos = false;
  bool _webAccess = true;
  bool _loaded = false;

  /// 用户自定义的设备名，null 表示用系统型号生成的默认名。
  String? get customAlias =>
      (_alias == null || _alias!.trim().isEmpty) ? null : _alias!.trim();

  bool get autoSavePhotos => _autoSavePhotos;

  /// 是否允许电脑浏览器访问。默认开启——打开浏览器输地址就能用，不用先去设置里找开关。
  bool get webAccess => _webAccess;

  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _alias = prefs.getString(_kAlias);
      _autoSavePhotos = prefs.getBool(_kAutoSavePhotos) ?? false;
      _webAccess = prefs.getBool(_kWebAccess) ?? true;
    } catch (_) {
      // 读不到就用默认值，不影响主流程
    }
    _loaded = true;
  }

  Future<void> setAlias(String? alias) async {
    final value = alias?.trim() ?? '';
    _alias = value.isEmpty ? null : value;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_alias == null) {
        await prefs.remove(_kAlias);
      } else {
        await prefs.setString(_kAlias, _alias!);
      }
    } catch (_) {}
  }

  Future<void> setAutoSavePhotos(bool value) async {
    _autoSavePhotos = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAutoSavePhotos, value);
    } catch (_) {}
  }

  Future<void> setWebAccess(bool value) async {
    _webAccess = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kWebAccess, value);
    } catch (_) {}
  }
}
