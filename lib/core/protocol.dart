/// 近传的局域网协议常量与协议版本。
///
/// 设计原则：只依赖 TCP / HTTP 单播，不依赖组播与 Bonjour，
/// 这样 iOS 不需要 [multicast entitlement]，Android 不需要组播锁，
/// 两端行为完全一致。
class Protocol {
  Protocol._();

  /// 协议版本，握手时用于判断兼容性。
  static const String version = '1';

  /// 传输服务监听端口。被占用时会回退到系统分配端口。
  static const int transferPort = 53318;

  /// 单个分片的字节数（2 MB）。太小则请求过多，太大则进度粒度粗、失败重传代价高。
  static const int chunkSize = 2 * 1024 * 1024;

  /// 设备探测的单次超时。同一网段 254 个地址批量探测时这个值决定总耗时。
  static const Duration probeTimeout = Duration(milliseconds: 420);

  /// 超过这个时间没有探测成功，设备视为离线。
  /// 只在搜索时用得上：一轮搜索结束后，太久没出现过的旧条目会被清掉。
  static const Duration offlineAfter = Duration(seconds: 40);

  /// 探测并发数。过高在部分路由器上会被限速，反而更慢。
  static const int probeConcurrency = 32;

  /// 每个分片请求的读超时。
  static const Duration chunkTimeout = Duration(seconds: 90);

  /// 单块失败后的最大重试次数（重试会从服务端实际已收字节处续传）。
  static const int maxRetries = 4;
}
