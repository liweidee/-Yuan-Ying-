// lib/modules/web_tab/services/ds_bridge_service.dart
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:yuanying/modules/web_tab/models/ds_env.dart';

class DsBridgeService {
  static const String handlerName = 'ds';

  static String buildSkeleton(DsEnv env) {
    return _template.replaceFirst('__ENV_PLACEHOLDER__', env.toJsonString());
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

  // ===== 事件系统 =====
  var listeners = {};
  function dispatch(name, data) {
    var arr = listeners[name] || [];
    for (var i = 0; i < arr.length; i++) {
      try { arr[i](data); } catch (e) { try { console.warn(e); } catch (_) {} }
    }
  }

  // ===== CSS 变量 =====
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

  // ===== ds 本体（全部顶层方法都内联在这） =====
  window.ds = {
    ready: false,
    env: ENV,

    // —— 网络 ——
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

    // —— UI ——
    toast: function(msg) { return call('toast', [msg]); },
    fullscreen: function(b) { return call('fullscreen', [b]); },
    tab: function(name) { return call('tab', [name]); },
    back: function() { return call('back', []); },
    reload: function() { return call('reload', []); },
    replay: function() { return call('replay', []); },

    // —— 打开页面 ——
    openVod: function(vod) { return call('openVod', [vod]); },
    openLive: function() { return call('openLive', []); },
    openKeep: function() { return call('openKeep', []); },
    openSetting: function() { return call('openSetting', []); },
    search: function(kw, opts) { return call('search', [kw, opts]); },
    vod: function(siteKey, id, name, pic) {
      return call('vod', [siteKey, id, name, pic]);
    },

    // —— 播放 ——
    play: function(url, t) { return call('play', [url, t]); },
    vodInline: function(vod) { return call('openVod', [vod]); },

    // —— 事件 ——
    on: function(name, cb) {
      (listeners[name] = listeners[name] || []).push(cb);
      return function() {
        var arr = listeners[name] || [];
        var i = arr.indexOf(cb);
        if (i >= 0) arr.splice(i, 1);
      };
    },

    // —— 存储 ——
    store: {
      get: function(k, ns) { return call('store.get', [k, ns]); },
      set: function(k, v, ns) { return call('store.set', [k, v, ns]); },
      del: function(k, ns) { return call('store.del', [k, ns]); }
    },

    // —— 信息 ——
    device: function() { return call('device', []); },
    site: function() { return call('site', []); },
    config: function() { return call('config', []); },
    history: function() { return call('history', []); },
    viewport: function() { return call('viewport', []); },

    // —— 播放器状态（stub） ——
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

    // —— 内部回调 ——
    __resolveDone: function(token, url) {
      return call('__resolveDone', [token, url]);
    }
  };

  // cache 与 store 相同
  window.ds.cache = window.ds.store;

  // ===== fm 别名 =====
  window.fm = window.ds;
  window.fongmiBridge = window.ds;
  window.fongmiClient = { mode: 'mobile', isLeanback: false };

  // ===== pan 网盘降级 =====
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
      if (o && o.type === 'http') return call('play', [o.url, o.title || '']);
      return Promise.resolve({ ok: false, error: 'unsupported' });
    }
  };
  window.ds.check = window.ds.pan.play;

  // ===== ui 分组 =====
  window.ds.ui = {
    getViewport: function() { return call('viewport', []); },
    restoreChrome: function() { return Promise.resolve(true); },
    setToolbar: function(b) { return Promise.resolve(true); }
  };

  // ===== ext 分组 =====
  window.ds.ext = {
    info: function() { return call('extInfo', []); },
    log: function(msg, data) {
      try { console.log('[WebExt]', msg, data); } catch (e) {}
      return Promise.resolve(true);
    },
    toast: function(msg) { return call('toast', [msg]); }
  };

  // ===== history 事件 =====
  try {
    var _ps = history.pushState;
    history.pushState = function() {
      _ps.apply(this, arguments);
      dispatch('fmurlchange', { url: location.href });
    };
  } catch (e) {}

  // ===== CSS 变量初始化 + ready =====
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
}