// ShellX browser pane bootstrap (A6 D10, D21–D23). Injected at document
// start in the top frame, page world. Everything it sends is data for the
// pane's console/network buffers and title; ShellX never takes commands
// from the page. Kept small and defensive: a page may break any global.
(function () {
  'use strict';
  if (window.__shellxBootstrap) return;
  Object.defineProperty(window, '__shellxBootstrap', { value: true });

  var send = (function () {
    try {
      if (window.webkit && window.webkit.messageHandlers &&
          window.webkit.messageHandlers.ShellxBrowser) {
        var h = window.webkit.messageHandlers.ShellxBrowser;
        return function (s) { h.postMessage(s); };
      }
      if (window.chrome && window.chrome.webview) {
        var w = window.chrome.webview;
        return function (s) { w.postMessage(s); };
      }
    } catch (e) {}
    return function () {};
  })();
  var stringify = JSON.stringify;
  var post = function (m) { try { send(stringify(m)); } catch (e) {} };
  var MAX = 2048;

  var text = function (v) {
    if (typeof v === 'string') return v;
    if (v instanceof Error) return String(v.stack || v.message || v);
    try {
      var s = stringify(v);
      return s === undefined ? String(v) : s;
    } catch (e) {
      return String(v);
    }
  };
  var join = function (args) {
    var out = '';
    for (var i = 0; i < args.length && out.length < MAX; i++) {
      out += (i ? ' ' : '') + text(args[i]);
    }
    return out.slice(0, MAX);
  };

  // Console (D22).
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (level) {
    var original = console[level];
    console[level] = function () {
      post({ t: 'console', level: level, text: join(arguments), url: location.href });
      if (original) return original.apply(console, arguments);
    };
  });
  window.addEventListener('error', function (e) {
    post({ t: 'console', level: 'error', url: location.href,
           text: join([e.message || 'Error', (e.filename || '') + ':' + (e.lineno || 0)]) });
  });
  window.addEventListener('unhandledrejection', function (e) {
    post({ t: 'console', level: 'error', url: location.href,
           text: join(['Unhandled rejection:', e.reason]) });
  });

  // Network (D23): resource timing, plus method/status from fetch and XHR.
  var net = function (m) { m.t = 'net'; m.url = String(m.url).slice(0, MAX); post(m); };
  try {
    new PerformanceObserver(function (list) {
      list.getEntries().forEach(function (e) {
        if (e.initiatorType === 'fetch' || e.initiatorType === 'xmlhttprequest') return;
        net({ url: e.name, type: e.entryType === 'navigation' ? 'navigation' : e.initiatorType,
              status: e.responseStatus || undefined, dur: e.duration,
              size: e.transferSize || undefined });
      });
    }).observe({ entryTypes: ['resource', 'navigation'] });
  } catch (e) {}
  if (window.fetch) {
    var originalFetch = window.fetch;
    window.fetch = function (input, init) {
      var started = Date.now();
      var method = (init && init.method) || (input && input.method) || 'GET';
      var url = (input && input.url) || String(input);
      return originalFetch.apply(this, arguments).then(function (r) {
        net({ url: r.url || url, type: 'fetch', method: method, status: r.status,
              dur: Date.now() - started });
        return r;
      }, function (err) {
        net({ url: url, type: 'fetch', method: method, dur: Date.now() - started });
        throw err;
      });
    };
  }
  if (window.XMLHttpRequest) {
    var open = XMLHttpRequest.prototype.open;
    var sendXhr = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function (method, url) {
      this.__shellx = { method: method, url: url };
      return open.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function () {
      var x = this, info = x.__shellx || {}, started = Date.now();
      x.addEventListener('loadend', function () {
        net({ url: x.responseURL || info.url, type: 'xmlhttprequest',
              method: info.method, status: x.status || undefined, dur: Date.now() - started });
      });
      return sendXhr.apply(this, arguments);
    };
  }

  // Title (D21): WKWebView has no title callback through the plugin.
  var lastTitle = null;
  var reportTitle = function () {
    if (document.title !== lastTitle) {
      lastTitle = document.title;
      post({ t: 'title', title: lastTitle });
    }
  };
  document.addEventListener('DOMContentLoaded', function () {
    reportTitle();
    try {
      new MutationObserver(reportTitle).observe(document.head || document.documentElement,
        { subtree: true, childList: true, characterData: true });
    } catch (e) {}
  });

  // Popups open in the same pane (D10) — macOS only; WebView2 uses its
  // popup policy. Harmless on Windows.
  if (window.webkit) {
    window.open = function (url) {
      if (url) location.assign(url);
      return null;
    };
    document.addEventListener('click', function (e) {
      var a = e.target && e.target.closest ? e.target.closest('a[target]') : null;
      if (a && a.target !== '_self' && a.href) {
        e.preventDefault();
        location.assign(a.href);
      }
    }, true);
  }
})();
