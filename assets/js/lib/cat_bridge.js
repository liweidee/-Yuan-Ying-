(function() {
  console.log('[CatBridge] IIFE started');

  if (typeof window === 'undefined') {
    window = globalThis || this;
  }

  if (!window._reqCallbacks) window._reqCallbacks = {};
  if (!window._localCallbacks) window._localCallbacks = {};

  window.req = async function(url, options) {
    return new Promise((resolve) => {
      const id = Date.now() + '_' + Math.random();
      window._reqCallbacks[id] = resolve;
      sendMessage('catReq', JSON.stringify({id, url, options: options || {}}));
    });
  };

  window.local = {
    get: async (scope, key) => {
      return new Promise((resolve) => {
        const id = Date.now() + '_' + Math.random();
        window._localCallbacks[id] = resolve;
        sendMessage('catLocalGet', JSON.stringify({id, scope, key}));
      });
    },
    set: async (scope, key, value) => {
      return new Promise((resolve) => {
        const id = Date.now() + '_' + Math.random();
        window._localCallbacks[id] = resolve;
        sendMessage('catLocalSet', JSON.stringify({id, scope, key, value}));
      });
    },
    delete: async (scope, key) => {
      return new Promise((resolve) => {
        const id = Date.now() + '_' + Math.random();
        window._localCallbacks[id] = resolve;
        sendMessage('catLocalDelete', JSON.stringify({id, scope, key}));
      });
    }
  };

  if (typeof globalThis !== 'undefined') {
    globalThis.req = window.req;
    globalThis.local = window.local;
  }

  console.log('[CatBridge] ready');
})();