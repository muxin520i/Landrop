/// 电脑浏览器访问页。全部内联，不引用任何 CDN——局域网里可能没有外网，
/// 页面必须自己就能跑起来。
String buildWebPage({required String alias}) {
  return _template.replaceAll('__ALIAS__', _escapeHtml(alias));
}

String _escapeHtml(String raw) => raw
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// 下载时给浏览器一个像样的类型，图片视频可以就地预览。
String contentTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot > 0 ? fileName.substring(dot + 1).toLowerCase() : '';
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'bmp':
      return 'image/bmp';
    case 'svg':
      return 'image/svg+xml';
    case 'mp4':
    case 'm4v':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';
    case 'mp3':
      return 'audio/mpeg';
    case 'm4a':
      return 'audio/mp4';
    case 'wav':
      return 'audio/wav';
    case 'aac':
      return 'audio/aac';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
    case 'md':
    case 'log':
      return 'text/plain; charset=utf-8';
    case 'json':
      return 'application/json';
    case 'zip':
      return 'application/zip';
    default:
      return 'application/octet-stream';
  }
}

/// 关闭电脑访问时，浏览器打开根路径看到的提示页。
const String webDisabledPage = '''<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>近传 · 电脑访问已关闭</title>
<style>
  :root{color-scheme:light dark}
  body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
    background:#f5f6fa;font:15px/1.7 -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif;color:#14161a}
  .box{max-width:340px;padding:32px 28px;background:#fff;border-radius:18px;text-align:center;
    box-shadow:0 8px 30px rgba(20,22,26,.06)}
  h1{font-size:17px;margin:0 0 10px}
  p{margin:0;color:#6b7280;font-size:13.5px}
  @media (prefers-color-scheme:dark){
    body{background:#101114;color:#eceef2}
    .box{background:#191b20;box-shadow:none}
    p{color:#9aa1ad}
  }
</style></head>
<body><div class="box">
  <h1>电脑访问已关闭</h1>
  <p>请在手机「近传」→ 设置 → 电脑访问里打开开关，再用同一个 Wi-Fi 刷新本页。</p>
</div></body></html>''';

const String _template = r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#3d5afe">
<title>近传 · __ALIAS__</title>
<style>
  :root{
    --bg:#f5f6fa; --card:#fff; --text:#14161a; --muted:#6b7280;
    --line:rgba(17,19,24,.08); --brand:#3d5afe; --brand-soft:rgba(61,90,254,.08);
    --ok:#16a34a; --bad:#dc2626; --track:rgba(17,19,24,.07);
    color-scheme:light;
  }
  @media (prefers-color-scheme:dark){
    :root{
      --bg:#101114; --card:#191b20; --text:#eceef2; --muted:#9aa1ad;
      --line:rgba(255,255,255,.08); --brand:#7b8cff; --brand-soft:rgba(123,140,255,.12);
      --ok:#4ade80; --bad:#f87171; --track:rgba(255,255,255,.08);
      color-scheme:dark;
    }
  }
  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
  body{
    margin:0;background:var(--bg);color:var(--text);
    font:14px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;
    padding:0 18px 48px;
  }
  .wrap{max-width:760px;margin:0 auto;min-height:calc(100vh - 74px);
    display:flex;flex-direction:column}
  header{display:flex;align-items:center;gap:12px;padding:26px 2px 20px}
  .logo{
    width:38px;height:38px;border-radius:11px;flex:none;
    background:linear-gradient(135deg,#5b74ff,#3d5afe 55%,#2f45d8);
    color:#fff;font-weight:700;font-size:16px;letter-spacing:.5px;
    display:flex;align-items:center;justify-content:center;
    box-shadow:0 6px 16px rgba(61,90,254,.28);
  }
  .head-text{min-width:0}
  h1{font-size:16px;margin:0;font-weight:700;letter-spacing:.2px}
  .sub{font-size:12px;color:var(--muted);margin:2px 0 0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .status{margin-left:auto;display:flex;align-items:center;gap:6px;font-size:12px;color:var(--muted);flex:none}
  .dot{width:6px;height:6px;border-radius:50%;background:var(--ok);box-shadow:0 0 0 3px rgba(22,163,74,.14)}
  .dot.off{background:var(--bad);box-shadow:0 0 0 3px rgba(220,38,38,.14)}

  .drop{
    position:relative;background:var(--card);border:1.5px dashed var(--line);
    border-radius:16px;padding:30px 20px;text-align:center;
    transition:border-color .18s,background .18s,transform .18s;
  }
  .drop.hover{border-color:var(--brand);background:var(--brand-soft)}
  .drop.busy{opacity:.6;pointer-events:none}
  .drop svg{width:34px;height:34px;color:var(--brand);opacity:.9}
  .drop-title{margin:12px 0 4px;font-size:14px;font-weight:600}
  .drop-title span{color:var(--brand)}
  .drop-hint{margin:0;font-size:12px;color:var(--muted)}
  #picker{display:none}

  .inbox{
    margin-top:14px;background:var(--card);border:1px solid var(--brand);
    border-radius:16px;overflow:hidden;display:none;
    box-shadow:0 8px 24px rgba(61,90,254,.14);
  }
  .inbox-head{display:flex;align-items:center;gap:8px;padding:11px 15px;
    background:var(--brand-soft);color:var(--brand);font-size:12.5px;font-weight:700}
  .inbox-head .n{margin-left:auto;font-weight:500;font-variant-numeric:tabular-nums}
  .inbox .ico{background:var(--brand-soft);color:var(--brand)}
  .inbox ul{border-radius:0}
  .inbox li{padding:12px 15px}
  .inbox .txt .desc{white-space:pre-wrap;word-break:break-word;max-height:84px;overflow:auto;
    color:var(--text);font-size:12.5px}
  .inbox .copy{border:0;font-family:inherit;cursor:pointer}

  .queue{margin-top:12px;display:flex;flex-direction:column;gap:8px}
  .q{
    background:var(--card);border-radius:12px;padding:11px 14px;
    display:flex;align-items:center;gap:12px;
  }
  .q .qname{font-size:13px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1}
  .q .qstate{font-size:12px;color:var(--muted);flex:none;font-variant-numeric:tabular-nums}
  .bar{height:3px;border-radius:2px;background:var(--track);overflow:hidden;margin-top:8px}
  .bar i{display:block;height:100%;width:0;background:var(--brand);border-radius:2px;transition:width .15s}
  .q-main{flex:1;min-width:0}
  .q.done .bar i{background:var(--ok)}
  .q.fail .bar i{background:var(--bad)}

  .section{margin-top:26px}
  .section-head{display:flex;align-items:baseline;gap:8px;margin:0 2px 10px}
  .section-head h2{font-size:13px;font-weight:600;margin:0}
  .count{font-size:12px;color:var(--muted)}
  .refresh{margin-left:auto;border:0;background:transparent;color:var(--brand);
    font-size:12.5px;font-weight:600;cursor:pointer;padding:4px 2px}
  .refresh:active{opacity:.6}

  ul{list-style:none;margin:0;padding:0;background:var(--card);border-radius:16px;overflow:hidden}
  li{display:flex;align-items:center;gap:13px;padding:13px 15px;border-top:1px solid var(--line)}
  li:first-child{border-top:0}
  .ico{
    width:38px;height:38px;border-radius:10px;flex:none;
    display:flex;align-items:center;justify-content:center;
    font-size:10px;font-weight:700;letter-spacing:.4px;
    background:var(--brand-soft);color:var(--brand);text-transform:uppercase;
  }
  .ico.img{background:rgba(22,163,74,.1);color:#16a34a}
  .ico.vid{background:rgba(147,51,234,.1);color:#9333ea}
  .ico.zip{background:rgba(234,88,12,.1);color:#ea580c}
  .ico.aud{background:rgba(219,39,119,.1);color:#db2777}
  @media (prefers-color-scheme:dark){
    .ico.img{background:rgba(74,222,128,.13);color:#4ade80}
    .ico.vid{background:rgba(192,132,252,.14);color:#c084fc}
    .ico.zip{background:rgba(251,146,60,.14);color:#fb923c}
    .ico.aud{background:rgba(244,114,182,.14);color:#f472b6}
  }
  .meta{min-width:0;flex:1}
  .name{margin:0;font-size:13.5px;font-weight:500;overflow:hidden;
    text-overflow:ellipsis;white-space:nowrap}
  .desc{margin:3px 0 0;font-size:11.5px;color:var(--muted);font-variant-numeric:tabular-nums}
  .dl{
    flex:none;text-decoration:none;color:var(--brand);font-size:12.5px;font-weight:600;
    padding:7px 13px;border-radius:9px;background:var(--brand-soft);
  }
  .dl:active{opacity:.65}
  .empty{padding:38px 16px;text-align:center;color:var(--muted);font-size:13px}
  .empty b{display:block;font-size:14px;color:var(--text);font-weight:600;margin-bottom:5px}

  footer{margin-top:auto;padding-top:26px;text-align:center;font-size:11.5px;
    color:var(--muted);line-height:1.8}
  @media (max-width:520px){
    body{padding:0 12px 40px}
    header{padding:20px 2px 16px}
    .dl{padding:7px 10px}
  }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="logo">近</div>
    <div class="head-text">
      <h1>近传</h1>
      <p class="sub" id="sub">__ALIAS__ · 局域网直连</p>
    </div>
    <div class="status"><span class="dot" id="dot"></span><span id="stateText">已连接</span></div>
  </header>

  <div class="drop" id="drop">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"
         stroke-linecap="round" stroke-linejoin="round">
      <path d="M12 16V4m0 0L7.5 8.5M12 4l4.5 4.5"/>
      <path d="M4 15v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/>
    </svg>
    <p class="drop-title">拖文件到这里，或 <span>点击选择</span></p>
    <p class="drop-hint">文件会直接存进手机的接收目录，可以一次选多个</p>
    <input type="file" id="picker" multiple>
  </div>

  <div class="inbox" id="inbox">
    <div class="inbox-head"><span>手机发来的</span><span class="n" id="inboxCount"></span></div>
    <ul id="inboxList"></ul>
  </div>

  <div class="queue" id="queue"></div>

  <section class="section">
    <div class="section-head">
      <h2>手机里的文件</h2>
      <span class="count" id="count"></span>
      <button class="refresh" id="refresh">刷新</button>
    </div>
    <ul id="list"><li class="empty">正在读取…</li></ul>
  </section>

  <footer>同一 Wi-Fi 下才能访问，换网络后地址会变<br>手机请保持「近传」在前台，锁屏后连接会断开</footer>
</div>

<script>
(function () {
  var drop = document.getElementById('drop');
  var picker = document.getElementById('picker');
  var listEl = document.getElementById('list');
  var queueEl = document.getElementById('queue');
  var countEl = document.getElementById('count');
  var refreshBtn = document.getElementById('refresh');
  var dotEl = document.getElementById('dot');
  var stateText = document.getElementById('stateText');
  var subEl = document.getElementById('sub');
  var inboxEl = document.getElementById('inbox');
  var inboxList = document.getElementById('inboxList');
  var inboxCount = document.getElementById('inboxCount');

  // 这台电脑的临时标识：刷新页面不变，关掉标签页就换新的
  var cid = '';
  try { cid = sessionStorage.getItem('ld_cid') || ''; } catch (_) {}
  if (!cid) {
    cid = 'c' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
    try { sessionStorage.setItem('ld_cid', cid); } catch (_) {}
  }

  var uploading = 0;
  var lastFiles = [];

  function esc(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
  }

  function bytes(n) {
    if (n < 1024) return n + ' B';
    var u = ['KB','MB','GB','TB'], i = -1;
    do { n /= 1024; i++; } while (n >= 1024 && i < u.length - 1);
    return (n >= 100 ? n.toFixed(0) : n.toFixed(1)) + ' ' + u[i];
  }

  function when(ts) {
    var d = new Date(ts * 1000);
    var now = new Date();
    var diff = (now - d) / 1000;
    if (diff < 60) return '刚刚';
    if (diff < 3600) return Math.floor(diff / 60) + ' 分钟前';
    var sameDay = d.toDateString() === now.toDateString();
    var hm = ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2);
    if (sameDay) return '今天 ' + hm;
    var md = ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
    return md + ' ' + hm;
  }

  function kind(name) {
    var ext = (name.split('.').pop() || '').toLowerCase();
    if (['jpg','jpeg','png','gif','webp','heic','heif','bmp','svg','tif','tiff'].indexOf(ext) >= 0) return 'img';
    if (['mp4','mov','m4v','mkv','avi','webm','flv','wmv'].indexOf(ext) >= 0) return 'vid';
    if (['zip','rar','7z','tar','gz','bz2','xz','dmg','iso'].indexOf(ext) >= 0) return 'zip';
    if (['mp3','wav','m4a','aac','flac','ogg','wma','ape'].indexOf(ext) >= 0) return 'aud';
    return '';
  }

  function tag(name) {
    var ext = (name.split('.').pop() || '').toLowerCase();
    if (!ext || ext === name.toLowerCase() || ext.length > 4) return 'FILE';
    return ext.toUpperCase();
  }

  function setOnline(ok) {
    dotEl.className = ok ? 'dot' : 'dot off';
    stateText.textContent = ok ? '已连接' : '连接中断';
  }

  function render(files) {
    lastFiles = files;
    countEl.textContent = files.length ? files.length + ' 个' : '';
    if (!files.length) {
      listEl.innerHTML = '<li class="empty"><b>还没有文件</b>上方拖一个上来，或者从手机传过来</li>';
      return;
    }
    var html = '';
    for (var i = 0; i < files.length; i++) {
      var f = files[i];
      var url = '/api/web/download?name=' + encodeURIComponent(f.name);
      html += '<li>' +
        '<div class="ico ' + kind(f.name) + '">' + esc(tag(f.name)) + '</div>' +
        '<div class="meta"><p class="name" title="' + esc(f.name) + '">' + esc(f.name) + '</p>' +
        '<p class="desc">' + bytes(f.size) + ' · ' + when(f.mtime) + '</p></div>' +
        '<a class="dl" href="' + url + '" download>下载</a></li>';
    }
    listEl.innerHTML = html;
  }

  function load() {
    fetch('/api/web/files', { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw 0; return r.json(); })
      .then(function (data) {
        setOnline(true);
        subEl.textContent = (data.alias || '__ALIAS__') + ' · 局域网直连';
        render(data.files || []);
      })
      .catch(function () { setOnline(false); });
  }

  // ---------------------------------------------- 手机发过来的，等这里接收

  function ping() {
    fetch('/api/web/ping?cid=' + encodeURIComponent(cid), { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw 0; return r.json(); })
      .then(function () { setOnline(true); })
      .catch(function () { setOnline(false); });
  }

  function doneItem(id) {
    fetch('/api/web/outbox?id=' + encodeURIComponent(id),
      { method: 'POST', cache: 'no-store' })
      .then(function () { pollInbox(); })
      .catch(function () {});
  }

  function fallbackCopy(text, cb) {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.top = '-1000px';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); cb(); } catch (_) {}
    document.body.removeChild(ta);
  }

  function copyText(text, btn) {
    function ok() {
      btn.textContent = '已复制';
      setTimeout(function () { btn.textContent = '复制'; }, 1500);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(ok).catch(function () {
        fallbackCopy(text, ok);
      });
    } else {
      fallbackCopy(text, ok);
    }
  }

  function renderInbox(items) {
    if (!items.length) {
      inboxEl.style.display = 'none';
      inboxList.innerHTML = '';
      inboxCount.textContent = '';
      return;
    }
    inboxEl.style.display = 'block';
    inboxCount.textContent = items.length + ' 个';

    var html = '';
    for (var i = 0; i < items.length; i++) {
      var it = items[i];
      if (it.text !== null && it.text !== undefined) {
        html += '<li class="txt">' +
          '<div class="ico">TXT</div>' +
          '<div class="meta"><p class="name">文本消息</p>' +
          '<p class="desc">' + esc(it.text) + '</p></div>' +
          '<button class="dl copy" data-copy="' + i + '">复制</button></li>';
      } else {
        var url = '/api/web/outbox?id=' + encodeURIComponent(it.id);
        html += '<li>' +
          '<div class="ico ' + kind(it.name) + '">' + esc(tag(it.name)) + '</div>' +
          '<div class="meta"><p class="name" title="' + esc(it.name) + '">' + esc(it.name) + '</p>' +
          '<p class="desc">' + bytes(it.size) + ' · ' + when(it.mtime) + '</p></div>' +
          '<a class="dl" href="' + url + '" download="' + esc(it.name) +
          '" data-id="' + esc(it.id) + '">保存</a></li>';
      }
    }
    inboxList.innerHTML = html;

    Array.prototype.forEach.call(inboxList.querySelectorAll('a[data-id]'), function (a) {
      a.addEventListener('click', function () {
        var id = a.getAttribute('data-id');
        // 浏览器已经开始下载，过一会儿再让手机把这条撤下
        setTimeout(function () { doneItem(id); }, 2500);
      });
    });
    Array.prototype.forEach.call(inboxList.querySelectorAll('button[data-copy]'), function (b) {
      b.addEventListener('click', function () {
        var it = items[parseInt(b.getAttribute('data-copy'), 10)];
        if (!it) return;
        copyText(it.text, b);
        doneItem(it.id);
      });
    });
  }

  function pollInbox() {
    fetch('/api/web/outbox?cid=' + encodeURIComponent(cid), { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw 0; return r.json(); })
      .then(function (data) { renderInbox(data.items || []); })
      .catch(function () {});
  }

  function addRow(name, size) {
    var row = document.createElement('div');
    row.className = 'q';
    row.innerHTML = '<div class="q-main"><div class="qname"></div>' +
      '<div class="bar"><i></i></div></div><div class="qstate"></div>';
    row.querySelector('.qname').textContent = name;
    row.querySelector('.qstate').textContent = '0%';
    queueEl.appendChild(row);
    return row;
  }

  function upload(file) {
    return new Promise(function (resolve) {
      var row = addRow(file.name, file.size);
      var bar = row.querySelector('.bar i');
      var state = row.querySelector('.qstate');
      var xhr = new XMLHttpRequest();
      xhr.open('POST', '/api/web/upload?name=' + encodeURIComponent(file.name) +
        '&size=' + file.size);
      xhr.upload.onprogress = function (e) {
        if (!e.lengthComputable) return;
        var p = Math.round(e.loaded / e.total * 100);
        bar.style.width = p + '%';
        state.textContent = p + '%';
      };
      xhr.onload = function () {
        var ok = xhr.status >= 200 && xhr.status < 300;
        row.className = 'q ' + (ok ? 'done' : 'fail');
        bar.style.width = '100%';
        state.textContent = ok ? '完成' : '失败';
        setTimeout(function () { row.remove(); }, ok ? 2500 : 5000);
        resolve();
      };
      xhr.onerror = function () {
        row.className = 'q fail';
        state.textContent = '网络中断';
        resolve();
      };
      xhr.send(file);
    });
  }

  function handleFiles(files) {
    if (!files || !files.length) return;
    var queue = Array.prototype.slice.call(files);
    uploading += queue.length;
    drop.classList.add('busy');
    var chain = Promise.resolve();
    queue.forEach(function (f) {
      chain = chain.then(function () { return upload(f); });
    });
    chain.then(function () {
      uploading -= queue.length;
      if (uploading <= 0) { uploading = 0; drop.classList.remove('busy'); }
      load();
    });
  }

  drop.addEventListener('click', function () { picker.click(); });
  picker.addEventListener('change', function () {
    handleFiles(picker.files);
    picker.value = '';
  });
  ['dragenter', 'dragover'].forEach(function (ev) {
    drop.addEventListener(ev, function (e) {
      e.preventDefault(); e.stopPropagation(); drop.classList.add('hover');
    });
  });
  ['dragleave', 'drop'].forEach(function (ev) {
    drop.addEventListener(ev, function (e) {
      e.preventDefault(); e.stopPropagation(); drop.classList.remove('hover');
    });
  });
  drop.addEventListener('drop', function (e) {
    if (e.dataTransfer && e.dataTransfer.files) handleFiles(e.dataTransfer.files);
  });
  window.addEventListener('dragover', function (e) { e.preventDefault(); });
  window.addEventListener('drop', function (e) { e.preventDefault(); });

  refreshBtn.addEventListener('click', load);
  setInterval(function () {
    if (!document.hidden && uploading === 0) load();
  }, 8000);

  load();

  // 心跳让手机知道有电脑开着；顺带把「手机发来的」拉下来
  ping();
  setInterval(ping, 4000);
  pollInbox();
  setInterval(function () {
    if (!document.hidden) pollInbox();
  }, 3000);
})();
</script>
</body>
</html>''';
