// SPDX-License-Identifier: MIT
//
// Renders the LuCI view's status part with a minimal LuCI shim (node only, no
// browser) and checks that strings coming from the router (hostnames, console
// names, nft errors, backend errors) are never inserted as HTML.
//
// LuCI's E(tag, attrs, children): a plain string child becomes innerHTML,
// strings inside an array become text nodes. The shim records both.
//
//   node tests/view.test.js
'use strict';
const fs = require('fs'), path = require('path');

const src = fs.readFileSync(path.join(__dirname, '../htdocs/luci-static/resources/view/ps5block/main.js'), 'utf8');
const EVIL = '<img src=x onerror=alert(1)>';
const htmlSinks = [];

function el(tag, attrs, children) {
	const n = { tag, attrs: attrs || {}, children: [], html: null };
	if (Array.isArray(attrs) || typeof attrs === 'string') { children = attrs; n.attrs = {}; }
	if (Array.isArray(children))
		children.forEach(c => { if (c != null) n.children.push(typeof c === 'object' ? c : { text: String(c) }); });
	else if (children && typeof children === 'object') n.children.push(children);
	else if (children != null) { n.html = String(children); htmlSinks.push(n.html); }
	n.appendChild = c => n.children.push(c);
	return n;
}
const E = (tag, a, c) => Array.isArray(tag) ? { tag: 'fragment', children: tag } : el(tag, a, c);
String.prototype.format = function() { let i = 0; const a = arguments; return this.replace(/%[sd]/g, () => String(a[i++])); };
const _ = s => s;

const notifications = [];
let lastUpload = null;
const L = {
	ui: {
		createHandlerFn: () => () => {}, addNotification: (t, n) => notifications.push(n),
		uploadFile: path => { lastUpload = path; return Promise.resolve({ name: 'upload.bin', size: 4096 }); },
	},
	// the payload send succeeds; any other method returns a failure carrying hostile text
	rpc: { declare: d => () => Promise.resolve(
		d.method === 'payload' ? { result: 0 } : { result: 1, error: 'invalid MAC: ' + EVIL }) },
};
const modules = {
	view: { extend: o => o }, form: {}, rpc: L.rpc, uci: {}, ui: L.ui, poll: {}, dom: {}, 'tools.widgets': {},
};
const body = src.replace(/^'require ([\w.]+)( as (\w+))?';$/mg, (m, mod, x, alias) =>
	`var ${alias || mod} = modules['${mod}'];`);
const view = new Function('E', '_', 'modules', 'window', body)(E, _, modules, { location: { reload() { throw new Error('reload on error'); } } });

const st = {
	version: '1.1.0', enabled: true, mode: 'mac', applied: true, error: 'nft: ' + EVIL, detected: 2, payload_port: 9021,
	consoles: [
		{ mac: 'f8:46:1c:11:22:33', ip: '192.168.1.50', hostname: EVIL, name: '', detected_by: 'oui', online: true, manual: false, manual_enabled: true, active: true },
		{ mac: '00:d9:d1:aa:bb:cc', ip: '-', hostname: '*', name: EVIL, detected_by: EVIL, online: false, manual: true, manual_enabled: false, active: false },
	],
	layers: { dns: { enabled: true, active: true, test: 'blocked' }, force_dns: { enabled: true, active: true, packets: 3 },
		dns_strict: { scope: 'podkop', podkop_routed: [ '192.168.1.48/30' ], enabled: true, active: true, packets: 0 },
		dot: { enabled: true, active: true, packets: 1 }, doh: { enabled: true, active: true, packets: 2, v4: 59, v6: 32 },
		l3: { enabled: true, active: false, packets: 0, v4: 0, v6: 0, refreshed: 0, interval: 20 } },
	integrations: { podkop: { installed: true, running: true } },
	warnings: [ 'multiple_consoles', 'podkop_strict:192.168.1.50', 'unknown:' + EVIL ],
};

let failed = 0;
function t(name, fn) {
	const pass = () => console.log('  ok   ' + name);
	const fail = e => { failed++; console.log('  FAIL ' + name + ': ' + e.message); };
	try {
		const r = fn();
		if (r && r.then) r.then(pass, fail); else pass();
	}
	catch (e) { fail(e); }
}
function texts(n, out = []) {
	if (!n) return out;
	if (n.text) out.push(n.text);
	if (n.html) out.push(n.html);
	(n.children || []).forEach(c => texts(c, out));
	return out;
}

let tree;
t('renderStatus does not throw', () => { tree = view.renderStatus(st); });
t('untrusted strings are shown as text', () => {
	const all = texts(tree).join('\n');
	if (!all.includes(EVIL)) throw new Error('hostile text not rendered at all');
});
t('no untrusted string reaches innerHTML', () => {
	const bad = htmlSinks.filter(h => h.includes(EVIL));
	if (bad.length) throw new Error(bad.length + ' sink(s): ' + bad[0].slice(0, 80));
});
t('status unavailable message is text', () => {
	htmlSinks.length = 0;
	view.renderStatus({ _error: EVIL });
	if (htmlSinks.some(h => h.includes(EVIL))) throw new Error('error text in innerHTML');
});
t('console action error: notification kept, no reload', () =>
	view.consoleAction('zz', 'include', '').then(() => {
		if (!notifications.length) throw new Error('no notification');
		if (htmlSinks.some(h => h.includes(EVIL))) throw new Error('error text in innerHTML');
	}));
t('Send payload button rendered for a console with an IP', () => {
	const btns = texts(tree).filter(x => x === 'Send payload');
	if (!btns.length) throw new Error('no Send payload button');
});
t('sendPayload uploads then sends and reports success as text', () => {
	htmlSinks.length = 0; notifications.length = 0; lastUpload = null;
	return view.sendPayload('192.168.1.50', EVIL).then(() => {
		if (lastUpload !== '/tmp/ps5block-payload/upload.bin') throw new Error('wrong upload path: ' + lastUpload);
		if (!notifications.length) throw new Error('no notification');
		if (htmlSinks.some(h => h.includes(EVIL))) throw new Error('label reached innerHTML');
	});
});

process.on('beforeExit', () => {
	console.log(failed ? `view tests failed: ${failed}` : 'view tests passed');
	process.exitCode = failed ? 1 : 0;
});
