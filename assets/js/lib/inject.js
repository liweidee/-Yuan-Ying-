// inject.js - 导入 htmlParser.js，并导出/挂载所有 drpy2 需要的标识符
import { pdfa, pdfh, pd, pjfh, pj, pjfa, pdfl, pq } from './htmlParser.js';

// 重新导出解析函数
export { pdfa, pdfh, pd, pjfh, pj, pjfa, pdfl, pq };

// ===== 实现 req（通过 /__bridge__ 代理，同步 XHR） =====
export function req(url, obj) {
  if (typeof window.douban !== 'undefined' && url.includes('$douban')) {
    url = url.replace(/\$douban/g, window.douban || '');
  }
  obj = obj || {};
  const method = (obj.method || 'GET').toUpperCase();
  const headers = obj.headers || {};

  // 安全处理 header 值
  for (const k in headers) {
    let val = headers[k];
    if (val === null || val === undefined) {
      delete headers[k];
      continue;
    }
    if (Array.isArray(val)) {
      headers[k] = val.join(', ');
    } else {
      headers[k] = String(val);
    }
  }

  let body = obj.body || null;
  if (obj.data) {
    const params = new URLSearchParams();
    for (const k in obj.data) params.append(k, obj.data[k]);
    body = params.toString();
    if (!headers['Content-Type'] && !headers['content-type']) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
  }

  const payload = JSON.stringify({ url, method, headers, body });
  const xhr = new XMLHttpRequest();
  xhr.open('POST', '/__bridge__', false);
  xhr.setRequestHeader('Content-Type', 'application/json');
  try {
    xhr.send(payload);
    if (xhr.status === 200) {
      const response = JSON.parse(xhr.responseText);
      if (obj.withHeaders) {
        return { content: response.body || '', headers: response.headers || {} };
      }
      return { content: response.body || '' };
    }
  } catch (e) {
    console.error('[req] error:', e.message);
  }
  return { content: '' };
}

// ===== 存储工具 =====
const store = {};
export const local = {
  get(rkey, k) { return store[`${rkey}_${k}`] || ''; },
  set(rkey, k, v) { store[`${rkey}_${k}`] = v; },
  delete(rkey, k) { delete store[`${rkey}_${k}`]; },
};

// ===== 其他工具函数 =====
export const joinUrl = (base, path) => {
  try { return new URL(path, base).href; } catch(e) { return base + path; }
};

export const buildUrl = (base, query) => {
  const url = new URL(base);
  for (const k in query) {
    if (query[k] !== null && query[k] !== undefined && query[k] !== '') {
      url.searchParams.set(k, query[k]);
    }
  }
  return url.toString();
};

export const stringify = (obj) => {
  try { return JSON.stringify(obj); } catch(e) { return '{}'; }
};

export const lists = { append: function(item) { if (!globalThis.__LISTS__) globalThis.__LISTS__ = []; globalThis.__LISTS__.push(item); } };

export const batchFetch = () => { console.warn('batchFetch not implemented'); };

export const print = (...args) => console.log('[drpy-print]', ...args);
export const log = print;
export const setResult2 = (result) => { globalThis.__RESULT__ = result; };

// ===== 重置 drpy2 状态（清理缓存和全局变量） =====
export function resetDrpyState() {
  // 清空 local 存储
  const storeKeys = Object.keys(store);
  for (const key of storeKeys) {
    delete store[key];
  }

  // 重置全局规则相关变量（如果它们存在）
  if (typeof window.rule !== 'undefined') {
    window.rule = {};
  }
  if (typeof window.fetch_params !== 'undefined') {
    window.fetch_params = {};
  }
  if (typeof window.VODS !== 'undefined') {
    window.VODS = [];
  }
  if (typeof window.VOD !== 'undefined') {
    window.VOD = {};
  }
  if (typeof window.LISTS !== 'undefined') {
    window.LISTS = [];
  }
  if (typeof window.TABS !== 'undefined') {
    window.TABS = [];
  }
  if (typeof window.MY_URL !== 'undefined') {
    window.MY_URL = '';
  }
  if (typeof window.HOST !== 'undefined') {
    window.HOST = '';
  }
  if (typeof window.play_url !== 'undefined') {
    window.play_url = '';
  }

  console.log('[drpy] resetDrpyState done');
}

// ===== 重新加载规则（快速切换站点） =====
export function reinit(ext) {
  resetDrpyState(); // 先重置状态，避免污染
  if (typeof init === 'function') {
    init(ext);
    console.log('[drpy] reinit with ext:', ext);
  } else {
    console.error('[drpy] reinit failed: init not found');
  }
}

// 挂载到全局
const mountGlobal = (target) => {
  if (!target) return;
  target.pdfa = pdfa;
  target.pdfh = pdfh;
  target.pd = pd;
  target.pjfh = pjfh;
  target.pj = pj;
  target.pjfa = pjfa;
  target.pdfl = pdfl;
  target.pq = pq;
  target.req = req;
  target.local = local;
  target.joinUrl = joinUrl;
  target.urljoin = joinUrl;
  target.urlJoin = joinUrl;
  target.buildUrl = buildUrl;
  target.stringify = stringify;
  target.lists = lists;
  target.batchFetch = batchFetch;
  target.print = print;
  target.log = log;
  target.setResult2 = setResult2;
  target.reinit = reinit;
  target.resetDrpyState = resetDrpyState;
};

mountGlobal(typeof window !== 'undefined' ? window : null);
mountGlobal(typeof globalThis !== 'undefined' ? globalThis : null);