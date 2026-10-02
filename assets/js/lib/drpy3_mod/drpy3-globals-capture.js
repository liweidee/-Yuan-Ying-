globalThis.__drpy3_globals_capture__ = {
    nativeWasm: globalThis.WebAssembly,
    nativeUint8ArrayFromBase64:
        typeof Uint8Array.fromBase64 === 'function' ? Uint8Array.fromBase64 : null,
};

// 保留原有的 fromBase64 补齐逻辑，只把变量名改掉
if (!globalThis.__drpy3_globals_capture__.nativeUint8ArrayFromBase64) {
    const B64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const B64_LOOKUP = new Int8Array(128).fill(-1);
    for (let i = 0; i < 64; i++) B64_LOOKUP[B64_ALPHABET.charCodeAt(i)] = i;
    B64_LOOKUP['-'.charCodeAt(0)] = 62;
    B64_LOOKUP['_'.charCodeAt(0)] = 63;
    const B64_RE = /^(?:[A-Za-z0-9+/-]{4})*(?:[A-Za-z0-9+/-]{2}==|[A-Za-z0-9+/-]{3}=)?$/;
    Uint8Array.fromBase64 = function (string) {
        const clean = String(string).replace(/\s/g, '');
        if (!B64_RE.test(clean)) throw new TypeError('Invalid base64 string');
        const stripPad = clean.replace(/=+$/, '');
        const out = new Uint8Array(Math.floor(stripPad.length * 3 / 4));
        let o = 0, buffer = 0, bits = 0;
        for (const ch of stripPad) {
            buffer = (buffer << 6) | B64_LOOKUP[ch.charCodeAt(0)];
            bits += 6;
            if (bits >= 8) { bits -= 8; out[o++] = (buffer >> bits) & 0xff; }
        }
        return out;
    };
}

globalThis.__drpy3_globals_capture__.nativeFetch = globalThis.fetch;
globalThis.__drpy3_globals_capture__.nativeTextEncoder = globalThis.TextEncoder;
globalThis.__drpy3_globals_capture__.nativeConsoleError = console.error;

console.error = function drpy3QuietConsoleError(...args) {
    if (typeof args[0] === 'string' && args[0].startsWith('[Script Loader]')) return;
    return globalThis.__drpy3_globals_capture__.nativeConsoleError.apply(this, args);
};