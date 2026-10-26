// drpy3-peer.js —— QuickJS 版：只负责恢复原生全局（如果有）
// 前提：globals-capture 已加载，drpy-core.min.js 已挂好 __drpy3_peer__

var __g = globalThis.__drpy3_globals_capture__ || {};

if (__g.nativeWasm && globalThis.WebAssembly !== __g.nativeWasm) {
    globalThis.WebAssembly = __g.nativeWasm;
}
if (__g.nativeFetch && globalThis.fetch !== __g.nativeFetch) {
    globalThis.fetch = __g.nativeFetch;
}
if (__g.nativeTextEncoder && globalThis.TextEncoder !== __g.nativeTextEncoder) {
    globalThis.TextEncoder = __g.nativeTextEncoder;
}
if (__g.nativeConsoleError) {
    console.error = __g.nativeConsoleError;
}