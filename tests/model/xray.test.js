'use strict'

module.exports = function ({ Xray, assert, eq }) {
  const NOW = 1700000000

  const status = {
    running: true,
    connectedKey: 'k2',
    subs: [
      { index: 0, host: 'sub.example.com', title: 'Main VPN',
        info: { upload: 1073741824, download: 1073741824, total: 107374182400, expire: NOW + 3 * 86400 } },
      { index: 1, host: 'other.example.com', title: '', info: {} }
    ],
    nodes: [
      { key: 'auto', name: 'Auto — best ping', address: '3 nodes', net: 'balancer', latency: '', sub: -1 },
      { key: 'k1', name: 'JP Tokyo', address: 'jp.example:443', net: 'vless/reality/raw', latency: '80ms', sub: 0 },
      { key: 'k2', name: 'US LA', address: 'us.example:443', net: 'trojan/tls/ws', latency: '', sub: 0 },
      { key: 'k3', name: 'DE', address: '[2001:db8::1]:443', net: 'hysteria2', latency: 'timeout', sub: 1 }
    ]
  }

  /* ---- groupsFromStatus ---- */
  {
    const t = Xray.groupsFromStatus(status, 1000, NOW)
    eq('group titles', t.groups.map(g => g.title), ['AUTO', 'MAIN VPN', 'OTHER.EXAMPLE.COM'])
    eq('flat nodes', t.nodes.length, 4)
    assert('running', t.running === true)
    assert('connected key', t.connectedKeys.k2 === true)
    assert('connected flag', Xray.findNodeByKey(t.nodes, 'k2').connected === true)
    assert('others not connected', Xray.findNodeByKey(t.nodes, 'k1').connected === false)
    eq('sub info label', t.groups[1].status, '2.00 GB / 100.00 GB · 3d left')
    eq('empty info label', t.groups[2].status, '')
  }
  {
    const t = Xray.groupsFromStatus(Object.assign({}, status, { running: false }), 1000, NOW)
    eq('stopped: nothing connected', Object.keys(t.connectedKeys).length, 0)
    eq('capped', Xray.groupsFromStatus(status, 2, NOW).nodes.length, 2)
    eq('bad input', Xray.groupsFromStatus(null).nodes.length, 0)
  }

  /* ---- labels ---- */
  eq('expired', Xray.subInfoLabel({ expire: NOW - 10 }, NOW), 'expired')
  eq('used only', Xray.subInfoLabel({ download: 2048 }, NOW), '2.0 KB used')
  eq('skipped none', Xray.skippedLabel({}), '')
  eq('skipped one reason', Xray.skippedLabel({ 'transport h2 was removed from Xray core (use XHTTP)': 2 }),
    '2 nodes skipped (transport h2 was removed from Xray core (use XHTTP))')
  eq('skipped many reasons', Xray.skippedLabel({ malformed: 1, 'x': 3 }), '4 nodes skipped (x, …)')

  /* ---- parseMetrics ---- */
  {
    const vars = {
      stats: { inbound: { 'socks-in': { uplink: 100, downlink: 1000 }, 'tun-in': { uplink: 50, downlink: 500 } },
               outbound: { proxy: { uplink: 999, downlink: 999 } } },
      observatory: { 'node-0': { alive: true, delay: 300 }, 'node-1': { alive: true, delay: 120 },
                     'node-2': { alive: false, delay: 5 } }
    }
    const a = Xray.parseMetrics(vars, null, 10000)
    eq('totals sum inbounds only', [a.upTotal, a.downTotal], [150, 1500])
    eq('no speed on first sample', [a.upSpeed, a.downSpeed], [0, 0])
    eq('auto pick alive lowest delay', a.autoPick, 'node-1')
    const vars2 = { stats: { inbound: { 'socks-in': { uplink: 1100, downlink: 3000 }, 'tun-in': { uplink: 50, downlink: 500 } } } }
    const b = Xray.parseMetrics(vars2, a, 12000)
    eq('speed over 2s', [b.upSpeed, b.downSpeed], [500, 1000])
    const c = Xray.parseMetrics({ stats: { inbound: {} } }, b, 14000)
    eq('counter reset -> no negative speed', [c.upSpeed, c.downSpeed], [0, 0])
    assert('garbage -> null', Xray.parseMetrics(null, null, 1) === null)
  }
  eq('auto pick name', Xray.autoPickName([{ tag: 'node-1', key: 'k3' }], status.nodes, 'node-1'), 'DE')
  eq('auto pick unknown', Xray.autoPickName([], status.nodes, 'node-1'), '')

  /* ---- latency helpers ---- */
  eq('latency ms label', Xray.latencyLabel('123ms'), '123ms')
  eq('latency timeout label', Xray.latencyLabel('TIMEOUT'), 'timeout')
  eq('latency error label', Xray.latencyLabel('error'), 'failed')
  assert('latency bad', Xray.latencyBad('timeout') === true)

  /* ---- filterNodes ---- */
  {
    const groups = Xray.groupsFromStatus(status, 1000, NOW).groups
    eq('filter by name', Xray.filterNodes(groups, 'tokyo').length, 1)
    eq('filter by net', Xray.filterNodes(groups, 'hysteria2')[0].nodes[0].key, 'k3')
    eq('filter no match', Xray.filterNodes(groups, 'zzz').length, 0)
    eq('filter empty returns all', Xray.filterNodes(groups, '').length, 3)
    eq('short query skips transport', Xray.filterNodes(groups, 'hy').length, 0)
  }

  /* ---- pickConnectTarget ---- */
  {
    const t = Xray.groupsFromStatus(Object.assign({}, status, { running: false }), 1000, NOW)
    eq('pick last key', Xray.pickConnectTarget(t, 'k3').name, 'DE')
    eq('pick auto when last', Xray.pickConnectTarget(t, 'auto').key, 'auto')
    eq('pick first real node', Xray.pickConnectTarget(t, 'nope').key, 'k1')
    assert('pick null on empty', Xray.pickConnectTarget({}, '') === null)
  }

  /* ---- heroLine ---- */
  {
    const t = Xray.groupsFromStatus(status, 1000, NOW)
    eq('hero connected', Xray.heroLine({ touch: t }), 'Connected (proxy) · US LA')
    eq('hero tun', Xray.heroLine({ touch: t, mode: 'tun' }), 'Connected (TUN) · US LA')
    const ta = Xray.groupsFromStatus(Object.assign({}, status, { connectedKey: 'auto' }), 1000, NOW)
    eq('hero auto', Xray.heroLine({ touch: ta, autoPick: 'DE' }), 'Connected (proxy) · Auto → DE')
    const off = Xray.groupsFromStatus(Object.assign({}, status, { running: false }), 1000, NOW)
    eq('hero disconnected', Xray.heroLine({ touch: off }), 'Off')
  }
  eq('hero unreachable', Xray.heroLine({ unreachable: true }), 'Xray manager unreachable')
  eq('hero checking', Xray.heroLine({}), 'Checking…')

  /* ---- heroTitle / heroState: the node leads, the state is a short caption ---- */
  {
    const t = Xray.groupsFromStatus(status, 1000, NOW)
    eq('title connected', Xray.heroTitle({ touch: t }), 'US LA')
    eq('state proxy', Xray.heroState({ touch: t }), 'Connected · system-proxy apps')
    eq('state tun', Xray.heroState({ touch: t, mode: 'tun' }), 'Connected · TUN')
    const ta = Xray.groupsFromStatus(Object.assign({}, status, { connectedKey: 'auto' }), 1000, NOW)
    eq('title auto pick', Xray.heroTitle({ touch: ta, autoPick: 'DE' }), 'Auto → DE')
    eq('title auto', Xray.heroTitle({ touch: ta }), 'Auto — best ping')
    const off = Xray.groupsFromStatus(Object.assign({}, status, { running: false }), 1000, NOW)
    eq('title off', Xray.heroTitle({ touch: off }), 'Not protected')
    eq('state off', Xray.heroState({ touch: off }), 'proxy')
    eq('state off tun', Xray.heroState({ touch: off, mode: 'tun' }), 'TUN')
    eq('title off with target', Xray.heroTitle({ touch: off, target: 'DE' }), 'Not protected')
    eq('title dropped', Xray.heroTitle({ touch: off, dropped: true }), 'Reconnecting')
    eq('state dropped', Xray.heroState({ touch: off, dropped: true }), 'Dropped · restarting the tunnel')
    eq('title blocked', Xray.heroTitle({ touch: off, blocked: true }), 'Blocked')
    eq('state blocked', Xray.heroState({ touch: off, blocked: true }), 'Kill switch · nothing leaks meanwhile')
    eq('title while connecting', Xray.heroTitle({ touch: off, target: 'DE', pending: 'connecting' }), 'DE')
    eq('state off names target', Xray.heroState({ touch: off, target: 'DE', mode: 'tun' }), 'TUN · next DE')
    eq('state skipped nodes', Xray.heroState({ touch: { nodes: [], connectedKeys: {} }, hasSubs: true }), 'No usable nodes · see below')
  }
  eq('state unreachable', Xray.heroState({ unreachable: true }), 'Manager not answering · run omarchy-xray doctor')
  eq('state checking', Xray.heroState({}), 'Checking…')
  eq('title checking', Xray.heroTitle({}), 'Xray')
  eq('title no subscription', Xray.heroTitle({ touch: { nodes: [], connectedKeys: {} } }), 'Xray')
  eq('state no subscription', Xray.heroState({ touch: { nodes: [], connectedKeys: {} } }), 'No subscription yet')
  eq('state connecting', Xray.heroState({ touch: { nodes: [], connectedKeys: {} }, pending: 'connecting' }), 'Connecting…')
  eq('state disconnecting', Xray.heroState({ touch: { nodes: [], connectedKeys: {} }, pending: 'disconnecting' }), 'Disconnecting…')
  eq('state unknown pending ignored', Xray.heroState({ touch: { nodes: [{ key: 'k' }], connectedKeys: {} }, pending: 'x' }), 'proxy')

  /* ---- names are tidied; the fastest measured node is known ---- */
  {
    const t = Xray.groupsFromStatus({ running: false, subs: [], nodes: [
      { key: 'a', name: '🇫🇮  Finland  ', latency: '448ms' },
      { key: 'b', name: 'Sweden', latency: '390ms' },
      { key: 'c', name: 'Germany', latency: 'timeout' }] }, 1000, NOW)
    eq('name whitespace collapsed', t.nodes[0].name, '🇫🇮 Finland')
    eq('fastest key', Xray.fastestKey(t.nodes), 'b')
    eq('fastest none', Xray.fastestKey([{ key: 'x', latency: 'timeout' }]), '')
  }

  /* ---- formatSpeed / formatBytes ---- */
  eq('speed zero', Xray.formatSpeed(0), '0 B/s')
  eq('speed bytes', Xray.formatSpeed(1023), '1023 B/s')
  eq('speed kb', Xray.formatSpeed(1024), '1.0 KB/s')
  eq('speed mb', Xray.formatSpeed(1578576), '1.5 MB/s')
  eq('speed gb', Xray.formatSpeed(2.5 * 1073741824), '2.50 GB/s')
  eq('bytes zero', Xray.formatBytes(0), '0 B')
  eq('bytes mb', Xray.formatBytes(3 * 1048576), '3.0 MB')
}
