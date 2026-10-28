// lib/modules/web_tab/services/ds_bridge_service.dart
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:yuanying/modules/web_tab/models/ds_env.dart';

class DsBridgeService {
  static const String handlerName = 'ds';

  static String buildSkeleton(DsEnv env) {
    final bridge =
        _template.replaceFirst('__ENV_PLACEHOLDER__', env.toJsonString());
    return '$bridge\n$_sniffHook';
  }

  static Future<void> emit(
    InAppWebViewController controller,
    String event,
    Map<String, dynamic> data,
  ) async {
    try {
      await controller.evaluateJavascript(
        source: 'window.__dsDispatch && window.__dsDispatch('
            '${jsonEncode(event)}, ${jsonEncode(data)});',
      );
    } catch (_) {}
  }

  // ============================================================
  // 桥接骨架（保持不变）
  // ============================================================
  static const String _template = r'''
(function() {
  if (window.__dsBridgeReady) return;
  window.__dsBridgeReady = true;

  var ENV = __ENV_PLACEHOLDER__;

  function call(method, args) {
    return window.flutter_inappwebview
      .callHandler('ds', { method: method, args: args || [] })
      .then(function(resp) {
        if (resp && resp.ok) return resp.data;
        throw new Error((resp && resp.error) || ('bridge error: ' + method));
      });
  }

  var listeners = {};
  function dispatch(name, data) {
    var arr = listeners[name] || [];
    for (var i = 0; i < arr.length; i++) {
      try { arr[i](data); } catch (e) { try { console.warn(e); } catch (_) {} }
    }
  }

  function applyCssVars(vars) {
    try {
      var s = document.documentElement.style;
      for (var k in vars) {
        if (vars[k] != null) s.setProperty(k, String(vars[k]));
      }
    } catch (e) {}
  }

  var _lastBgTime = 0;
  window.__dsDispatch = function(name, data) {
    if (name === 'dsbackground') {
      _lastBgTime = (data && data.time) || Date.now();
      dispatch('fmpause', {});
      return;
    }
    if (name === 'dsforeground') {
      var t = (data && data.time) || Date.now();
      var pausedMs = _lastBgTime > 0 ? (t - _lastBgTime) : 0;
      _lastBgTime = 0;
      dispatch('fmresume', { pausedMs: pausedMs });
      return;
    }
    if (name === 'dsviewport') {
      if (data && data.keyboardBottom != null)
        applyCssVars({ '--fm-keyboard-bottom': data.keyboardBottom + 'px' });
      if (data && data.statusBarHeight != null)
        applyCssVars({ '--fm-status-bar-height': data.statusBarHeight + 'px' });
      if (data && data.navigationBarHeight != null)
        applyCssVars({ '--fm-navigation-bar-height': data.navigationBarHeight + 'px' });
      if (data && data.width != null)
        applyCssVars({ '--fm-web-width': data.width + 'px' });
      if (data && data.height != null)
        applyCssVars({ '--fm-web-height': data.height + 'px' });
      dispatch('dsviewport', data);
      dispatch('fmviewport', data);
      return;
    }
    if (name === 'dstheme') {
      if (data && data.theme) {
        applyCssVars({
          '--ds-dark': data.theme.isDark ? '1' : '0',
          '--ds-theme-primary': data.theme.primary || '#FF512F',
        });
      }
      dispatch('dstheme', data);
      return;
    }
    dispatch(name, data);
  };

  window.ds = {
    ready: false,
    env: ENV,

    req: function(url, opts) { return call('req', [url, opts]); },
    res: function(url, opts) {
      if (!url) return '';
      var gw = (ENV && ENV.gwPort) || 5575;
      var s = 'http://127.0.0.1:' + gw + '/webResource?url=' + encodeURIComponent(url);
      if (opts && opts.headers) {
        try { s += '&headers=' + encodeURIComponent(JSON.stringify(opts.headers)); }
        catch (e) {}
      }
      return s;
    },

    toast: function(msg) { return call('toast', [msg]); },
    fullscreen: function(b) { return call('fullscreen', [b]); },
    tab: function(name) { return call('tab', [name]); },
    back: function() { return call('back', []); },
    reload: function() { return call('reload', []); },
    replay: function() { return call('replay', []); },

    openVod: function(vod) { return call('openVod', [vod]); },
    openLive: function() { return call('openLive', []); },
    openKeep: function() { return call('openKeep', []); },
    openSetting: function() { return call('openSetting', []); },
    search: function(kw, opts) { return call('search', [kw, opts]); },
    vod: function(siteKey, id, name, pic) {
      return call('vod', [siteKey, id, name, pic]);
    },

    play: function(url, t) { return call('play', [url, t]); },
    vodInline: function(vod) { return call('openVod', [vod]); },

    on: function(name, cb) {
      (listeners[name] = listeners[name] || []).push(cb);
      return function() {
        var arr = listeners[name] || [];
        var i = arr.indexOf(cb);
        if (i >= 0) arr.splice(i, 1);
      };
    },

    store: {
      get: function(k, ns) { return call('store.get', [k, ns]); },
      set: function(k, v, ns) { return call('store.set', [k, v, ns]); },
      del: function(k, ns) { return call('store.del', [k, ns]); }
    },

    device: function() { return call('device', []); },
    site: function() { return call('site', []); },
    config: function() { return call('config', []); },
    history: function() { return call('history', []); },
    viewport: function() { return call('viewport', []); },

    stat: function() {
      return Promise.resolve({
        state: 'idle', speed: 0, duration: 0, position: 0,
        url: '', title: '', artist: '', artwork: ''
      });
    },
    ctrl: function(action) {
      return Promise.resolve({ ok: true, noop: true });
    },
    preloadArtwork: function(url, title) {
      return Promise.resolve(true);
    },

    __resolveDone: function(token, url) {
      return call('__resolveDone', [token, url]);
    }
  };

  window.ds.cache = window.ds.store;

  window.fm = window.ds;
  window.fongmiBridge = window.ds;
  window.fongmiClient = { mode: 'mobile', isLeanback: false };

  window.ds.pan = {
    check: function(items) {
      return Promise.resolve((items || []).map(function(it) {
        return {
          state: 'unsupported',
          normalized_url: it && it.url || '',
          cache_hit: false, expires_at: 0, checked_at: Date.now()
        };
      }));
    },
    play: function(o) {
      if (!o || !o.url) return Promise.resolve({ ok: false, error: 'invalid' });
      return call('pan.play', [o]);
    }
  };
  window.ds.check = window.ds.pan.play;

  window.ds.ui = {
    getViewport: function() { return call('viewport', []); },
    restoreChrome: function() { return Promise.resolve(true); },
    setToolbar: function(b) { return Promise.resolve(true); }
  };

  window.ds.ext = {
    info: function() { return call('extInfo', []); },
    log: function(msg, data) {
      try { console.log('[WebExt]', msg, data); } catch (e) {}
      return Promise.resolve(true);
    },
    toast: function(msg) { return call('toast', [msg]); }
  };

  try {
    var _ps = history.pushState;
    history.pushState = function() {
      _ps.apply(this, arguments);
      dispatch('fmurlchange', { url: location.href });
    };
  } catch (e) {}

  function markReady() {
    if (!document.documentElement) {
      setTimeout(markReady, 10);
      return;
    }
    var si = ENV.safeInsets || {};
    var th = ENV.theme || {};
    applyCssVars({
      '--fm-safe-top': (si.top || 0) + 'px',
      '--fm-safe-bottom': (si.bottom || 0) + 'px',
      '--fm-safe-left': (si.left || 0) + 'px',
      '--fm-safe-right': (si.right || 0) + 'px',
      '--fm-chrome-mode': 'edge',
      '--fm-status-bar-height': (si.top || 0) + 'px',
      '--fm-navigation-bar-height': (si.bottom || 0) + 'px',
      '--fm-web-height': (window.innerHeight || 0) + 'px',
      '--fm-web-width': (window.innerWidth || 0) + 'px',
      '--fm-keyboard-bottom': '0px',
      '--fm-gesture-left': '0px',
      '--fm-gesture-right': '0px',
      '--fm-system-bars-hidden': '0',
      '--ds-safe-top': (si.top || 0) + 'px',
      '--ds-theme-primary': th.primary || '#FF512F',
      '--ds-dark': th.isDark ? '1' : '0'
    });
    window.ds.ready = true;
    setTimeout(function() {
      try { window.dispatchEvent(new Event('dsready')); } catch (e) {}
      try { window.dispatchEvent(new Event('fmsdk')); } catch (e) {}
    }, 0);
  }
  markReady();
})();
''';

  // ============================================================
  // 嗅探 Hook：5 路并行 + PerformanceObserver
  // ============================================================
  static const String _sniffHook = r'''
(function() {
  if (window.__dsSniffHookInstalled) return;
  window.__dsSniffHookInstalled = true;

  var reported = {};

  function isMedia(u) {
    if (!u || typeof u !== 'string') return false;
    if (u.indexOf('blob:') === 0 || u.indexOf('data:') === 0) return false;
    if (/\.(js|css|png|jpg|jpeg|gif|webp|svg|woff|ttf)(\?|#|$)/i.test(u)) return false;
    return /\.(m3u8|mp4|flv|mpd|mkv|mov|m4v|ts|webm)(\?|#|$)/i.test(u)
      || /videoplayback|\/video\/|\/stream\//i.test(u);
  }

  function reportMedia(url, title) {
    if (!isMedia(url)) return;
    if (reported[url]) return;
    reported[url] = true;
    try {
      window.flutter_inappwebview.callHandler('ds', {
        method: 'sniffedVideo',
        args: [{ url: url, title: title || document.title || '' }]
      });
      try { console.log('[sniff] report:', url); } catch (e) {}
    } catch (e) {}
  }

  // ============ 路径 1：PerformanceObserver（buffered:true 捕获历史资源） ============
  try {
    var po = new PerformanceObserver(function(list) {
      var entries = list.getEntries();
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        var name = entry.name;
        if (!name) continue;
        var type = entry.initiatorType || '';
        // 不过滤类型，全都试一遍（避免漏掉）
        reportMedia(name, '');
      }
    });
    po.observe({ entryTypes: ['resource'] });
  } catch (e) { try { console.log('[sniff] PerformanceObserver failed:', e); } catch (_) {} }

  // ============ 路径 2：定时扫 Performance API（兜底，防止 buffered 丢历史） ============
  function scanPerformance() {
    try {
      var entries = performance.getEntriesByType('resource');
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].name) reportMedia(entries[i].name, '');
      }
    } catch (e) {}
  }

  // ============ 路径 3：扫 video/source/link ============
  function scanDOM() {
    try {
      document.querySelectorAll('video, source').forEach(function(el) {
        if (el.src) reportMedia(el.src, el.title || '');
        if (el.currentSrc) reportMedia(el.currentSrc, el.title || '');
      });
    } catch (e) {}
    try {
      document.querySelectorAll('link[rel="preload"], link[rel="prefetch"]').forEach(function(l) {
        if (l.href) reportMedia(l.href, '');
      });
    } catch (e) {}
  }

  // ============ 路径 4：Hook play/load/src setter ============
  try {
    var origPlay = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function() {
      try {
        if (this.src) reportMedia(this.src, this.title || '');
        if (this.currentSrc) reportMedia(this.currentSrc, this.title || '');
      } catch (e) {}
      return origPlay.apply(this, arguments);
    };
  } catch (e) {}

  try {
    var origLoad = HTMLMediaElement.prototype.load;
    HTMLMediaElement.prototype.load = function() {
      try {
        if (this.src) reportMedia(this.src, this.title || '');
      } catch (e) {}
      return origLoad.apply(this, arguments);
    };
  } catch (e) {}

  try {
    var desc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
    if (desc && desc.set) {
      var origSet = desc.set;
      Object.defineProperty(HTMLMediaElement.prototype, 'src', {
        configurable: true,
        enumerable: desc.enumerable,
        get: desc.get,
        set: function(v) {
          try { reportMedia(v, this.title || ''); } catch (e) {}
          return origSet.call(this, v);
        }
      });
    }
  } catch (e) {}

  // ============ 路径 5：Hook fetch / XHR ============
  try {
    var origFetch = window.fetch;
    if (origFetch) {
      window.fetch = function(input) {
        try {
          var url = typeof input === 'string' ? input : (input && input.url);
          if (url) reportMedia(url);
        } catch (e) {}
        return origFetch.apply(this, arguments);
      };
    }
  } catch (e) {}

  try {
    var origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      try {
        if (url) {
          var absUrl = url;
          if (url.indexOf('http') !== 0 && url.indexOf('blob:') !== 0) {
            try { absUrl = new URL(url, location.href).href; } catch (e) {}
          }
          reportMedia(absUrl);
        }
      } catch (e) {}
      return origOpen.apply(this, arguments);
    };
  } catch (e) {}

  // ============ 路径 6：MutationObserver 实时监听 DOM ============
  try {
    var mo = new MutationObserver(function(mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var m = mutations[i];
        if (m.type === 'childList') {
          for (var j = 0; j < m.addedNodes.length; j++) {
            var node = m.addedNodes[j];
            if (!node || node.nodeType !== 1) continue;
            if (node.tagName === 'VIDEO' || node.tagName === 'SOURCE') {
              if (node.src) reportMedia(node.src, node.title || '');
              if (node.currentSrc) reportMedia(node.currentSrc, node.title || '');
            }
            if (node.querySelectorAll) {
              node.querySelectorAll('video, source').forEach(function(el) {
                if (el.src) reportMedia(el.src, el.title || '');
              });
            }
          }
        } else if (m.type === 'attributes' && m.target) {
          var t = m.target;
          if (t.tagName === 'VIDEO' || t.tagName === 'SOURCE') {
            if (t.src) reportMedia(t.src, t.title || '');
          }
        }
      }
    });
    var root = document.documentElement || document.body;
    if (root) {
      mo.observe(root, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['src']
      });
    }
  } catch (e) {}

  // ============ 定时兜底 ============
  setInterval(function() {
    scanPerformance();
    scanDOM();
  }, 2000);

  setTimeout(function() {
    scanPerformance();
    scanDOM();
  }, 500);

  setTimeout(scanPerformance, 3000);

  // ============ 网盘链接检测（保持不变） ============
  var CLOUD_REGEX = /(pan\.quark\.cn|pan\.baidu\.com|pan\.xunlei\.com|aliyundrive\.com|alipan\.com|115\.com|123pan\.com|cloud\.189\.cn|drive\.uc\.cn)/i;
  var CODE_REGEX = /(?:提取码|密码|pwd)[\s:：=]*([a-zA-Z0-9]{4})/i;

  function extractCloudLinks() {
    var links = [];
    var seen = {};
    function add(url, label) {
      if (!url || seen[url]) return;
      if (!CLOUD_REGEX.test(url)) return;
      seen[url] = true;
      var code = '';
      try {
        var m = (label || '').match(CODE_REGEX);
        if (m) code = m[1];
      } catch (e) {}
      links.push({ url: url, label: label || '', extractCode: code });
    }
    try {
      document.querySelectorAll('a[href]').forEach(function(a) {
        add(a.href || '', (a.textContent || '').trim().slice(0, 100));
      });
    } catch (e) {}
    try {
      var body = document.body ? (document.body.innerText || '') : '';
      var urlRegex = /(https?:\/\/(?:pan\.quark\.cn|pan\.baidu\.com|pan\.xunlei\.com|aliyundrive\.com|alipan\.com|115\.com|123pan\.com|cloud\.189\.cn|drive\.uc\.cn)[^\s"'<>]+)/gi;
      var matches = body.match(urlRegex) || [];
      matches.forEach(function(u) { add(u, ''); });
    } catch (e) {}
    try {
      var walker = document.createTreeWalker(
        document.body || document.documentElement,
        NodeFilter.SHOW_TEXT, null, false
      );
      var node;
      while ((node = walker.nextNode())) {
        var t = (node.nodeValue || '').trim();
        if (t && CLOUD_REGEX.test(t)) {
          var m2 = t.match(/(https?:\/\/[^\s"'<>]+)/i);
          if (m2) add(m2[1], t.slice(0, 100));
        }
      }
    } catch (e) {}
    return links;
  }

  function reportCloudLinks() {
    var links = extractCloudLinks();
    if (!links.length) return;
    try {
      window.flutter_inappwebview.callHandler('ds', {
        method: 'reportCloudLinks',
        args: [links]
      });
    } catch (e) {}
  }

  setInterval(reportCloudLinks, 3000);
  setTimeout(reportCloudLinks, 1500);
})();
''';
}