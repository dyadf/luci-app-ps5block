'use strict';
'require view';
'require form';
'require rpc';
'require uci';
'require ui';
'require poll';
'require dom';
'require tools.widgets as widgets';

var callStatus = rpc.declare({ object: 'ps5block', method: 'status', expect: { '': {} } });
var callApply = rpc.declare({ object: 'ps5block', method: 'apply', expect: { '': {} } });
var callRefresh = rpc.declare({ object: 'ps5block', method: 'refresh', expect: { '': {} } });
var callToggle = rpc.declare({ object: 'ps5block', method: 'toggle', params: [ 'enabled' ], expect: { '': {} } });
var callConsole = rpc.declare({ object: 'ps5block', method: 'console', params: [ 'mac', 'action', 'name' ], expect: { '': {} } });
var callPayloadPrepare = rpc.declare({ object: 'ps5block', method: 'payload_prepare', expect: { '': {} } });
var callPayloadSend = rpc.declare({ object: 'ps5block', method: 'payload', params: [ 'target', 'name' ], expect: { '': {} } });
var callPayloadCheck = rpc.declare({ object: 'ps5block', method: 'payload_check', params: [ 'target' ], expect: { '': {} } });

var PAYLOAD_PATH = '/tmp/ps5block-payload/upload.bin';

var COLORS = { ok: '#2e7d32', warn: '#e65100', bad: '#c62828', off: '#757575' };

function badge(kind, text) {
	return E('span', {
		'style': 'display:inline-block;padding:1px 8px;border-radius:10px;font-size:90%;white-space:nowrap;color:#fff;background:' + (COLORS[kind] || COLORS.off)
	}, text);
}

function fmtTime(ts) {
	if (!ts) return _('never');
	return new Date(ts * 1000).toLocaleString();
}

function consoleLabel(c) {
	if (c.name) return c.name;
	if (c.hostname && c.hostname !== '*') return c.hostname;
	return _('PlayStation');
}

function warningText(code) {
	var p = String(code).split(':'), arg = p.slice(1).join(':');
	switch (p[0]) {
	case 'no_consoles':
		return _('No consoles to block: none detected and none added. Turn the console on (it must get an address from this router) or add its MAC address in the "Consoles" section below.');
	case 'multiple_consoles':
		return _('Several PlayStation consoles were detected. With auto-detection on, all of them are blocked; use "Exclude" in the list below for any console that should keep updating.');
	case 'not_applied':
		return _('Blocking is enabled, but the firewall rules are not loaded. Press "Re-apply rules" or check the error below.');
	case 'podkop_domains':
		return _('The podkop configuration contains PlayStation domains. Remove them: podkop would hand out fake IPs for these domains and interfere with the DNS block.');
	case 'podkop_ip':
		return _('Console %s is routed completely through podkop and strict DNS is off. podkop can take its DNS before the redirect; set "Strict DNS" to "Auto" or "On".').format(arg);
	case 'podkop_strict':
		return _('Console %s is routed completely through podkop. Strict DNS is applied to it automatically, so it can only use the router as DNS server.').format(arg);
	case 'adguard':
		return _('AdGuard Home is running. If it serves DNS on port 53 instead of dnsmasq, the DNS layer does not work; add the update domains to AdGuard Home\'s blocklist as well.');
	case 'dns_missing':
		return _('The DNS block entry is missing from dnsmasq. Press "Re-apply rules".');
	default:
		return code;
	}
}

function layerRow(name, desc, l, details) {
	var state;
	if (!l || !l.enabled) state = badge('off', _('Off'));
	else if (l.active) state = badge('ok', _('Active'));
	else state = badge('bad', _('Not loaded'));

	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td', 'style': 'width:22%' }, E('strong', {}, name)),
		E('td', { 'class': 'td', 'style': 'width:12%' }, state),
		E('td', { 'class': 'td' }, [ E('div', {}, desc), details ? E('div', { 'style': 'opacity:.8;font-size:90%' }, Array.isArray(details) ? details : [ details ]) : '' ])
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			callStatus().catch(function(e) { return { _error: String(e) }; }),
			uci.load('ps5block')
		]);
	},

	checkPort: function(target) {
		return callPayloadCheck(target).then(function(res) {
			if (!res || !res.status) {
				ui.addNotification(null, E('p', [ _('Port check failed.') ]), 'danger');
				return;
			}
			var port = res.port || 9021, ip = res.ip || target;
			if (res.status === 'open')
				ui.addNotification(null, E('p', [ _('Port %d on %s is open: the payload loader is ready.').format(port, ip) ]), 'info');
			else if (res.status === 'closed')
				ui.addNotification(null, E('p', [ _('Port %d on %s is closed. Start the payload loader on the console first.').format(port, ip) ]), 'warning');
			else
				ui.addNotification(null, E('p', [ _('No IP address for this console; turn it on and connect it to this router.') ]), 'warning');
		});
	},

	sendPayload: function(target, label, port) {
		port = port || 9021;
		return callPayloadPrepare().then(function() {
			return ui.uploadFile(PAYLOAD_PATH);
		}).then(function(info) {
			var size = (info && info.size) || 0;
			/* the backend checks the port before it transmits to the console,
			   so a closed port means nothing was sent (the upload is removed) */
			return callPayloadSend(target, 'upload.bin').then(function(res) {
				var st = res && res.status;
				if (st === 'sent' || (res && res.result === 0))
					ui.addNotification(null, E('p', [ _('Payload sent to %s (%d bytes) and deleted from the router.').format(label, size) ]), 'info');
				else if (st === 'closed')
					ui.addNotification(null, E('p', [ _('The payload loader is not listening on port %d of %s; nothing was sent. Start the loader on the console and try again.').format(port, target) ]), 'warning');
				else if (st === 'no_ip')
					ui.addNotification(null, E('p', [ _('No IP address for this console; turn it on and connect it to this router.') ]), 'warning');
				else
					ui.addNotification(null, E('p', [ _('Sending the payload failed: %s').format((res && (res.error || res.result)) || '?') ]), 'danger');
			});
		}).catch(function(e) {
			var msg = String((e && e.message) || e || '');
			if (!/cancel/i.test(msg))
				ui.addNotification(null, E('p', [ _('Payload upload failed: %s').format(msg) ]), 'danger');
		});
	},

	consoleAction: function(mac, action, name) {
		return callConsole(mac, action, name || '').then(function(res) {
			if (res && res.result !== 0) {
				/* keep the page so the message stays visible */
				ui.addNotification(null, E('p', [ _('Failed: %s').format(res.error || res.result) ]), 'danger');
				return;
			}
			window.location.reload();
		});
	},

	renderStatus: function(st) {
		var self = this;

		if (!st || st._error || st.version === undefined)
			return E('div', { 'class': 'alert-message warning' }, [
				_('Status is not available (%s). Try reloading the page; if it persists, run "/etc/init.d/rpcd restart" on the router.').format(st && st._error ? st._error : 'rpcd') ]);

		var L = st.layers || {}, consoles = st.consoles || [], global = st.mode === 'global';
		var blocked = consoles.filter(function(c) { return c.active; }).length;

		/* ---- headline ---- */
		var headline, hk;
		if (!st.enabled) { hk = 'off'; headline = _('Blocking is disabled'); }
		else if (!st.applied || st.error) { hk = 'bad'; headline = _('Error: rules are not loaded'); }
		else if (global) { hk = 'ok'; headline = _('Updates are blocked for the whole network'); }
		else if (blocked > 0) { hk = 'ok'; headline = _('Updates are blocked for %d console(s)').format(blocked); }
		else { hk = 'warn'; headline = _('Enabled, but no console is selected yet'); }

		var toggleBtn = E('button', {
			'class': 'cbi-button ' + (st.enabled ? 'cbi-button-reset' : 'cbi-button-apply'),
			'click': ui.createHandlerFn(this, function() {
				return callToggle(!st.enabled).then(function() { window.location.reload(); });
			})
		}, st.enabled ? _('Disable blocking') : _('Enable blocking'));

		var head = E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:12px;margin-bottom:12px' }, [
			E('span', { 'style': 'font-size:130%;font-weight:bold;color:' + COLORS[hk] }, '● ' + headline),
			toggleBtn,
			E('button', { 'class': 'cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, function() {
				return callApply().then(function() { ui.addNotification(null, E('p', _('Rules re-applied.')), 'info'); return self.updateStatus(); });
			}) }, _('Re-apply rules')),
			E('span', { 'style': 'opacity:.7' }, [ _('Mode: %s').format(global ? _('whole network') : _('consoles by MAC')) + ' · v' + st.version ])
		]);

		var out = [ head ];

		/* ---- warnings ---- */
		(st.warnings || []).forEach(function(w) {
			var info = String(w).indexOf('podkop_strict') === 0;
			out.push(E('div', { 'class': 'alert-message ' + (info ? 'info' : 'warning'), 'style': 'margin:6px 0' }, [ warningText(w) ]));
		});
		if (st.error)
			out.push(E('div', { 'class': 'alert-message error' }, [ E('strong', {}, _('nftables error:')), E('pre', { 'style': 'white-space:pre-wrap' }, [ st.error ]) ]));

		/* ---- consoles ---- */
		var ct = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Console')), E('th', { 'class': 'th' }, _('MAC address')),
				E('th', { 'class': 'th' }, _('IP address')), E('th', { 'class': 'th' }, _('Network')),
				E('th', { 'class': 'th' }, _('Found by')), E('th', { 'class': 'th' }, _('Update block')),
				E('th', { 'class': 'th' }, '')
			])
		]);

		if (!consoles.length)
			ct.appendChild(E('tr', { 'class': 'tr placeholder' }, E('td', { 'class': 'td', 'colspan': 7 },
				E('em', {}, _('No PlayStation consoles found. Turn the console on and connect it to this router, then wait a few seconds.')))));

		consoles.forEach(function(c) {
			var how = { oui: _('MAC vendor (Sony)'), hostname: _('device name'), manual: _('added by hand') }[c.detected_by] || c.detected_by;
			var state, actions = [];

			if (!st.enabled) state = badge('off', _('Disabled'));
			else if (global) state = badge('ok', _('Blocked (whole network)'));
			else if (c.active) state = badge('ok', _('Blocked'));
			else if (c.manual && !c.manual_enabled) state = badge('warn', _('Excluded'));
			else state = badge('warn', _('Not blocked'));

			if (!global) {
				if (c.active)
					actions.push(E('button', { 'class': 'cbi-button cbi-button-negative', 'click': ui.createHandlerFn(self, 'consoleAction', c.mac, 'exclude', '') }, _('Exclude')));
				else
					actions.push(E('button', { 'class': 'cbi-button cbi-button-positive', 'click': ui.createHandlerFn(self, 'consoleAction', c.mac, 'include', consoleLabel(c)) }, _('Block')));
				if (c.manual)
					actions.push(' ', E('button', { 'class': 'cbi-button', 'title': _('Remove from the list of manually added consoles'), 'click': ui.createHandlerFn(self, 'consoleAction', c.mac, 'remove', '') }, _('Forget')));
			}

			if (c.ip && c.ip !== '-') {
				actions.push(' ', E('button', {
					'class': 'cbi-button',
					'title': _('Check whether the console is listening for payloads on port %d (one-shot loaders may treat the check as a connection).').format(st.payload_port || 9021),
					'click': ui.createHandlerFn(self, 'checkPort', c.ip)
				}, _('Check port')));
				actions.push(' ', E('button', {
					'class': 'cbi-button cbi-button-action',
					'title': _('Upload a homebrew payload (ELF/bin) and send it to this console on port %d. The console must already run a payload loader. The file is deleted from the router right after sending.').format(st.payload_port || 9021),
					'click': ui.createHandlerFn(self, 'sendPayload', c.ip, consoleLabel(c), st.payload_port || 9021)
				}, _('Send payload')));
			}

			ct.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, E('strong', {}, [ consoleLabel(c) ])),
				E('td', { 'class': 'td' }, E('code', {}, [ c.mac.toUpperCase() ])),
				E('td', { 'class': 'td' }, [ c.ip !== '-' ? c.ip : '—' ]),
				E('td', { 'class': 'td' }, c.online ? badge('ok', _('online')) : badge('off', _('offline'))),
				E('td', { 'class': 'td' }, [ how ]),
				E('td', { 'class': 'td' }, state),
				E('td', { 'class': 'td' }, actions)
			]));
		});

		var detTitle = _('Consoles');
		if (st.detected > 1) detTitle += ' — ' + _('%d detected').format(st.detected);
		out.push(E('h3', {}, detTitle), ct);

		/* ---- protection layers ---- */
		var dnsTest = { blocked: badge('ok', _('update domain does not resolve')), resolves: badge('bad', _('update domain still resolves!')), error: badge('warn', _('test failed')), skipped: '' }[L.dns && L.dns.test] || '';
		var strictDesc;
		if (L.dns_strict && L.dns_strict.scope === 'podkop')
			strictDesc = _('Applied to clients routed completely by podkop: %s').format((L.dns_strict.podkop_routed || []).join(', '));
		else if (L.dns_strict && L.dns_strict.scope === 'all')
			strictDesc = _('Applied to all blocked devices.');
		else
			strictDesc = _('Not needed: no blocked device is routed completely by podkop.');

		var lt = E('table', { 'class': 'table' }, [
			layerRow(_('1. DNS block'), _('dnsmasq answers "domain does not exist" for the update servers.'), L.dns, dnsTest ? [ _('Check on the router: '), dnsTest ] : null),
			layerRow(_('2. DNS redirect'), _('Any DNS request (port 53) to any server is answered by the router, so manual DNS on the console does not help.'), L.force_dns, [ (L.force_dns && L.force_dns.server && L.force_dns.server !== 'router') ? _('Forced to %s. ').format(L.force_dns.server) : _('Forced to the router. '), _('Redirected requests: %d').format((L.force_dns || {}).packets || 0) ]),
			layerRow(_('3. Strict DNS'), _('External DNS is dropped before podkop can intercept it; the console must use the router as DNS server.'), L.dns_strict, [ strictDesc, ' ', _('Dropped: %d').format((L.dns_strict || {}).packets || 0) ]),
			layerRow(_('4. DoT / DoQ'), _('Encrypted DNS on port 853 is dropped.'), L.dot, _('Dropped: %d').format((L.dot || {}).packets || 0)),
			layerRow(_('5. DoH'), _('Connections to well-known public DNS/DoH resolvers are dropped (port 53 is redirected instead).'), L.doh,
				_('Resolvers in the list: %d IPv4, %d IPv6. Dropped: %d').format((L.doh || {}).v4 || 0, (L.doh || {}).v6 || 0, (L.doh || {}).packets || 0)),
			layerRow(_('6. Update servers (L3)'), _('Update server IP addresses are dropped even if the console already knows them.'), L.l3,
				_('Addresses: %d IPv4, %d IPv6. Updated: %s (every %d min). Dropped: %d').format((L.l3 || {}).v4 || 0, (L.l3 || {}).v6 || 0, fmtTime((L.l3 || {}).refreshed), (L.l3 || {}).interval || 20, (L.l3 || {}).packets || 0))
		]);

		out.push(E('h3', {}, _('Protection layers')), lt);
		out.push(E('div', { 'class': 'cbi-page-actions', 'style': 'text-align:left' }, [
			E('button', { 'class': 'cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, function() {
				return callRefresh().then(function() { ui.addNotification(null, E('p', _('Refreshing the update server list in the background. The counters update in a few seconds.')), 'info'); });
			}) }, _('Refresh update server list now'))
		]));

		/* ---- integrations ---- */
		var I = st.integrations || {};
		function integ(name, o, note) {
			if (!o || !o.installed) return E('li', {}, [ E('strong', {}, name), ': ', _('not installed') ]);
			return E('li', {}, [ E('strong', {}, name), ': ', o.running ? badge('ok', _('running')) : badge('off', _('stopped')), ' — ', note ]);
		}
		out.push(E('h3', {}, _('Compatibility')), E('ul', {}, [
			integ('podkop', I.podkop, _('compatible: the block runs before podkop (priority -170 vs -150), console traffic to update servers never reaches the proxy.')),
			integ('zapret / zapret2', I.zapret, _('compatible: dropped packets never reach zapret queues.')),
			integ('https-dns-proxy (DoH)', I.doh_proxy, _('compatible: works as dnsmasq upstream; the dnsmasq block answers first.')),
			integ('AdGuard Home', I.adguardhome, _('if it replaces dnsmasq on port 53, add the update domains to its blocklist.'))
		]));

		return E('div', {}, out);
	},

	updateStatus: function() {
		var self = this;
		return callStatus().then(function(st) {
			var node = document.getElementById('ps5block-status');
			if (node) dom.content(node, self.renderStatus(st));
		});
	},

	renderHelp: function() {
		var steps = [
			[ _('Connect the console to this router'), _('Wired or Wi-Fi. The console must get its address from this router (DHCP). PS5 has different MAC addresses for LAN cable and Wi-Fi; both are detected automatically.') ],
			[ _('Set DNS to "Automatic"'), _('PS5: Settings → Network → Settings → Set Up Internet Connection → your network → Advanced Settings → DNS Settings: Automatic. Manual DNS is also redirected, but "Automatic" is the most reliable, especially with podkop.') ],
			[ _('Turn off automatic updates'), _('PS5: Settings → System → System Software → System Software Update and Settings → turn off "Download Update Files Automatically" and "Install Update Files Automatically".') ],
			[ _('Delete an update that was already downloaded'), _('The router cannot remove files that are already on the console. If a "system update downloaded" notice is shown, delete that download on the console before it is installed.') ],
			[ _('Enable blocking here and check the console list'), _('The console appears in the list above with status "Blocked". If you have several consoles, all are blocked; use "Exclude" for the ones that may update.') ],
			[ _('Restart the console'), _('Turn it off completely (not rest mode) and on again so it forgets cached DNS answers.') ],
			[ _('Check'), _('PS5: Settings → System → System Software → System Software Update and Settings → Update System Software → Update Using Internet. The console must report an error instead of finding a new version. Games, patches and PSN keep working.') ]
		];

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('How to set up the console')),
			E('ol', { 'style': 'margin-left:1.5em' }, steps.map(function(s) {
				return E('li', { 'style': 'margin-bottom:6px' }, [ E('strong', {}, s[0]), E('br'), s[1] ]);
			})),
			E('p', { 'style': 'opacity:.8' }, _('Limits: a console connected to another network (phone hotspot, another router) or updated from a USB drive is not covered by the router.'))
		]);
	},

	render: function(data) {
		var st = data[0], self = this, m, s, o;

		m = new form.Map('ps5block', null, null);

		/* ---------- settings ---------- */
		s = m.section(form.NamedSection, 'main', 'ps5block', _('Settings'));
		s.addremove = false;
		s.tab('general', _('General'));
		s.tab('layers', _('Protection layers'));
		s.tab('advanced', _('Advanced'));

		o = s.taboption('general', form.Flag, 'enabled', _('Enable blocking'));
		o.rmempty = false;

		o = s.taboption('general', form.ListValue, 'mode', _('Blocking mode'),
			_('<b>Consoles only</b>: rules apply only to PlayStation consoles (by MAC), all other devices are untouched. <b>Whole network</b>: rules apply to every client of the selected networks; use it if the console MAC changes or you want no exceptions. podkop and zapret keep working in both modes.'));
		o.value('mac', _('Consoles only (by MAC address)'));
		o.value('global', _('Whole network'));
		o.default = 'mac';

		o = s.taboption('general', form.Flag, 'autodetect', _('Detect consoles automatically'),
			_('Finds consoles by the Sony Interactive Entertainment MAC prefix and by device name (DHCP leases and ARP). New consoles are added as soon as they get an address.'));
		o.default = '1';
		o.depends('mode', 'mac');

		o = s.taboption('general', widgets.NetworkSelect, 'lan_iface', _('Networks'), _('Networks where consoles (or, in "Whole network" mode, all clients) are connected. Usually "lan"; add a guest network if the console uses it.'));
		o.multiple = true;
		o.nocreate = true;
		o.default = 'lan';

		/* layers - consoles mode */
		o = s.taboption('layers', form.Flag, 'dns_block', _('DNS block'), _('dnsmasq answers NXDOMAIN for the update domains. Always network-wide; no other device uses these domains.'));
		o.default = '1';

		o = s.taboption('layers', form.Flag, 'force_dns', _('DNS redirect'), _('Answer every DNS request of the console from the router, even with manual DNS on the console.'));
		o.default = '1'; o.depends('mode', 'mac');
		o = s.taboption('layers', form.DynamicList, 'dns_server', _('Force DNS to this server'),
			_('Send the console\'s DNS to these server(s) instead of the router (overrides podkop/AdGuard); with several, queries are spread across them. Leave empty to use the router\'s dnsmasq. Make sure the server(s) are reachable — a dead server here means no DNS for the console. With a non-router server the built-in DNS block does not apply to the console; blocking then relies on the IP/DoT/DoH layers or that server\'s own filtering.'));
		o.datatype = 'ipaddr';
		o.placeholder = _('router (dnsmasq)');
		o.depends('force_dns', '1');
		o = s.taboption('layers', form.ListValue, 'dns_strict', _('Strict DNS'), _('Drop console DNS requests to external servers instead of redirecting them. "Auto" enables it only for consoles that podkop routes completely, because podkop would otherwise intercept their DNS first.'));
		o.value('auto', _('Auto (only when podkop routes the console)'));
		o.value('1', _('On'));
		o.value('0', _('Off'));
		o.default = 'auto'; o.depends('mode', 'mac');
		o = s.taboption('layers', form.Flag, 'block_dot', _('Block DoT / DoQ'), _('Drop encrypted DNS on port 853.'));
		o.default = '1'; o.depends('mode', 'mac');
		o = s.taboption('layers', form.Flag, 'block_doh', _('Block DoH resolvers'), _('Drop connections to well-known public DNS-over-HTTPS resolvers.'));
		o.default = '1'; o.depends('mode', 'mac');
		o = s.taboption('layers', form.Flag, 'l3_block', _('Block update servers by IP (L3)'), _('Drop update server addresses directly. The list is refreshed by the router in the background.'));
		o.default = '1'; o.depends('mode', 'mac');

		/* layers - whole network mode (safer defaults) */
		o = s.taboption('layers', form.Flag, 'global_force_dns', _('DNS redirect'), _('Answer every DNS request in the network from the router. Compatible with podkop (it needs clients to use the router DNS anyway).'));
		o.default = '1'; o.depends('mode', 'global');
		o = s.taboption('layers', form.Flag, 'global_dns_strict', _('Strict DNS'), _('Drop DNS requests to external servers for every client. Devices with manual DNS lose name resolution; enable only if needed.'));
		o.default = '0'; o.depends('mode', 'global');
		o = s.taboption('layers', form.Flag, 'global_block_dot', _('Block DoT / DoQ'), _('Drop port 853 for every client. Browsers and phones with "Private DNS" fall back to normal DNS.'));
		o.default = '0'; o.depends('mode', 'global');
		o = s.taboption('layers', form.Flag, 'global_block_doh', _('Block DoH resolvers'), _('Drop connections to public DoH resolvers for every client. Some apps may show DNS errors before falling back.'));
		o.default = '0'; o.depends('mode', 'global');
		o = s.taboption('layers', form.Flag, 'global_l3_block', _('Block update servers by IP (L3)'), _('Update servers share CDN addresses with other sites; for the whole network this can block unrelated content. Off by default.'));
		o.default = '0'; o.depends('mode', 'global');

		/* advanced */
		o = s.taboption('advanced', form.Value, 'refresh_interval', _('Refresh interval (minutes)'), _('How often the update server address list and the console list are refreshed.'));
		o.datatype = 'range(5,1440)';
		o.default = '20';

		o = s.taboption('advanced', form.Value, 'payload_port', _('Payload port'), _('TCP port the console\'s homebrew payload loader listens on. Default 9021. Used by the "Send payload" button in the console list.'));
		o.datatype = 'port';
		o.placeholder = '9021';
		o.default = '9021';

		o = s.taboption('advanced', form.ListValue, 'blocklist', _('What to block (DNS)'),
			_('<b>Updates only</b>: system software update servers; games, the store and PSN keep working. <b>All PSN servers</b>: also blocks downloads (incl. games), store, sign-in and social — the console is cut off from Sony. <b>Custom</b>: only the list below.'));
		o.value('updates', _('Updates only (recommended)'));
		o.value('all', _('All PSN servers'));
		o.value('custom', _('Custom list only'));
		o.default = 'updates';

		o = s.taboption('advanced', form.DynamicList, 'domain', _('Extra blocked domains'), _('Blocked together with all subdomains, on top of the preset above (for "Custom", this is the whole list).'));
		o.datatype = 'hostname';

		o = s.taboption('advanced', form.DynamicList, 'resolver', _('Resolvers for the address list'), _('Public DNS servers the router asks for update server addresses.'));
		o.datatype = 'ipaddr';

		/* ---------- consoles ---------- */
		s = m.section(form.GridSection, 'console', _('Consoles added by hand'),
			_('Add a console that is not detected automatically, or keep a detected console unblocked by adding it with "Block" turned off. The buttons in the status list above do the same.'));
		s.anonymous = true;
		s.addremove = true;
		s.nodescriptions = true;

		o = s.option(form.Flag, 'enabled', _('Block'));
		o.default = '1';
		o.editable = true;
		o.rmempty = false;

		o = s.option(form.Value, 'name', _('Name'));
		o.placeholder = 'PS5';

		o = s.option(form.Value, 'mac', _('MAC address'));
		o.datatype = 'macaddr';
		o.rmempty = false;
		((st && st.consoles) || []).forEach(function(c) {
			if (c.detected_by !== 'manual')
				o.value(c.mac, '%s (%s, %s)'.format(c.mac.toUpperCase(), consoleLabel(c), c.ip));
		});

		return m.render().then(function(mapEl) {
			var statusNode = E('div', { 'id': 'ps5block-status', 'class': 'cbi-section' }, self.renderStatus(st));
			poll.add(function() { return self.updateStatus(); }, 10);

			return E([], [
				E('h2', {}, _('PS5 Update Block')),
				E('div', { 'class': 'cbi-map-descr' }, _('Blocks PlayStation 5 system software updates on the router. Games, patches, PSN and all other devices keep working.')),
				statusNode,
				mapEl,
				self.renderHelp()
			]);
		});
	}
});
