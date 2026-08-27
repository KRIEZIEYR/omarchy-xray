'use strict'

module.exports = function ({ V2rayA, assert, eq }) {
  /* ---- shellQuote ---- */
  eq('quote simple', V2rayA.shellQuote('abc'), "'abc'")
  eq('quote empty', V2rayA.shellQuote(''), "''")
  eq('quote embedded single quote', V2rayA.shellQuote("it's"), "'it'\\''s'")
  {
    // Real security check: bash must round-trip hostile input untouched.
    const { execFileSync } = require('child_process')
    const hostile = [
      "$(touch /tmp/v2a-pwned-$(id -u))",
      "it's a \"test\" with $HOME and `id`",
      "multi\nline; rm -rf /",
      "'; malicious '",
    ]
    for (const input of hostile) {
      let out = ''
      try {
        out = execFileSync('bash', ['-c', 'printf %s ' + V2rayA.shellQuote(input)], { encoding: 'utf8' })
      } catch (e) { out = '<exec failed: ' + e.message + '>' }
      eq('quote roundtrip: ' + JSON.stringify(input), out, input)
    }
  }

  /* ---- parseResponse ---- */
  {
    const raw = '{"code":"SUCCESS","message":null,"data":{"token":"t1"}}\n200\n__V2A_RC__0'
    const r = V2rayA.parseResponse(raw)
    assert('response ok', r.ok === true)
    eq('response token', r.data.token, 't1')
    eq('response http', r.httpStatus, 200)
    eq('response exit', r.exit, 0)
  }
  {
    const r = V2rayA.parseResponse('{"code":"FAIL","message":"wrong password","data":null}\n401\n__V2A_RC__0')
    assert('401 flagged unauthorized', r.unauthorized === true && r.ok === false)
    assert('401 message surfaced', r.message.indexOf('wrong password') !== -1)
  }
  {
    const r = V2rayA.parseResponse('curl: (7) Failed to connect\n000\n__V2A_RC__7')
    assert('conn refused friendly', r.message === 'v2rayA is not reachable (connection refused)')
    assert('not reachable flag', r.reachable === false)
  }
  {
    const r = V2rayA.parseResponse('')
    assert('empty output handled', r.ok === false && r.message !== '')
  }
  {
    // stderr noise before the body must not break parsing
    const raw = 'Note: some verbose junk\n{"code":"SUCCESS","data":{"running":true}}\n200\n__V2A_RC__0'
    const r = V2rayA.parseResponse(raw)
    assert('noise tolerated', r.ok === true && r.data.running === true)
  }

  /* ---- which keys ---- */
  eq('server key', V2rayA.whichKey({ _type: 'server', id: 3 }), 's:3')
  eq('sub server key', V2rayA.whichKey({ _type: 'subscriptionServer', id: 5, sub: 1 }), 'ss:1:5')
  eq('subscription key', V2rayA.whichKey({ _type: 'subscription', id: 2 }), 'sub:2')

  /* ---- parseTouch ---- */
  {
    const data = {
      running: true,
      networkPaused: false,
      touch: {
        servers: [
          { id: 1, _type: 'server', name: 'Home', address: 'a.example:443', net: 'vless', pingLatency: '30ms' }
        ],
        subscriptions: [
          {
            id: 1, _type: 'subscription', host: 'sub.example.com', remarks: 'Main',
            status: 'ok', info: '', autoSelect: false,
            servers: [
              { id: 1, _type: 'subscriptionServer', name: 'JP-1', address: 'jp1.example:443', net: 'vless-reality-vision', pingLatency: '' },
              { id: 2, _type: 'subscriptionServer', name: 'US-1', address: 'us1.example:443', net: 'trojan', pingLatency: '150ms' }
            ]
          }
        ],
        connectedServer: [{ _type: 'subscriptionServer', id: 2, sub: 0, outbound: 'proxy' }]
      }
    }
    const t = V2rayA.parseTouch(data)
    eq('group count', t.groups.length, 2)
    eq('flat nodes', t.nodes.length, 3)
    assert('running', t.running === true)
    assert('connected key tracked', t.connectedKeys['ss:0:2'] === true)
    const us1 = V2rayA.findNodeByKey(t.nodes, 'ss:0:2')
    assert('connected node found', us1 !== null)
    assert('node connected flag', us1.connected === true)
    const which = us1.which
    eq('which type', which._type, 'subscriptionServer')
    eq('which sub 0-based', which.sub, 0)
    eq('which id 1-based', which.id, 2)

    // heroLine with this state
    const line = V2rayA.heroLine({ touch: t })
    assert('hero shows node name', line.indexOf('US-1') !== -1 && line.indexOf('Connected') === 0)
  }

  /* ---- latency helpers ---- */
  eq('latency ms label', V2rayA.latencyLabel('123ms'), '123ms')
  eq('latency timeout label', V2rayA.latencyLabel('TIMEOUT'), 'timeout')
  assert('latency good', V2rayA.latencyGood('300ms') === true)
  assert('latency not good', V2rayA.latencyGood('500ms') === false)
  assert('latency bad', V2rayA.latencyBad('timeout') === true)

  {
    let cache = {}
    cache = V2rayA.mergeLatencies(cache, [{ _type: 'subscriptionServer', id: 1, sub: 0, pingLatency: '88ms' }])
    eq('merge into cache', cache['ss:0:1'], '88ms')
    const t = V2rayA.parseTouch({
      running: true,
      touch: { servers: [], subscriptions: [], connectedServer: [] }
    })
    // simulate a node and apply cached latency
    t.nodes.push(V2rayA.toNode({ id: 1, name: 'X', address: '', net: '' }, 0))
    V2rayA.applyLatencies(t, cache)
    eq('applyLatencies overrides', t.nodes[0].latency, '88ms')
  }

  /* ---- buildLatencyQuery ---- */
  {
    const q = V2rayA.buildLatencyQuery(
      [{ which: { _type: 'server', id: 1 } }, { which: { _type: 'subscriptionServer', id: 2, sub: 0 } }],
      100,
      ''
    )
    assert('query has whiches', q.indexOf('whiches=') === 0)
    const json = JSON.parse(decodeURIComponent(q.split('&')[0].substring(8)))
    eq('query roundtrip len', json.length, 2)
    eq('query roundtrip first', json[0], { _type: 'server', id: 1 })
  }
  {
    const q = V2rayA.buildLatencyQuery([{ which: { _type: 'server', id: 1 } }], 100, 'https://www.gstatic.com/generate_204')
    assert('testUrl appended', q.indexOf('&testUrl=') !== -1)
  }
  {
    const many = []
    for (let i = 0; i < 250; i++) many.push({ which: { _type: 'server', id: i + 1 } })
    const q = V2rayA.buildLatencyQuery(many, 100, '')
    const json = JSON.parse(decodeURIComponent(q.split('&')[0].substring(8)))
    eq('cap at 100', json.length, 100)
  }

  /* ---- filterNodes ---- */
  {
    const groups = [{ title: 'MAIN', nodes: [{ name: 'JP Tokyo', address: 'jp:443' }, { name: 'US LA', address: 'us:443' }] }]
    eq('filter matches name', V2rayA.filterNodes(groups, 'tokyo').length, 1)
    eq('filter no match keeps empty out', V2rayA.filterNodes(groups, 'zzz').length, 0)
    eq('filter empty returns all groups', V2rayA.filterNodes(groups, '').length, 1)
  }

  /* ---- pickConnectTarget ---- */
  {
    const state = {
      nodes: [
        { key: 's:1', name: 'A', which: {}, connected: false },
        { key: 's:2', name: 'B', which: {}, connected: true },
        { key: 's:3', name: 'C', which: {}, connected: false }
      ]
    }
    eq('pick last key', V2rayA.pickConnectTarget(state, 's:3').name, 'C')
    eq('pick fallback connected', V2rayA.pickConnectTarget(state, 'nope').name, 'B')
    eq('pick first when nothing else', V2rayA.pickConnectTarget({ nodes: [{ key: 'x', name: 'Z', which: {} }] }, 'nope').name, 'Z')
    assert('pick null on empty', V2rayA.pickConnectTarget({}, '') === null)
  }

  /* ---- heroLine states ---- */
  eq('hero unreachable', V2rayA.heroLine({ unreachable: true }), 'v2rayA unreachable')
  eq('hero first run', V2rayA.heroLine({ firstRun: true }), 'No v2rayA account — open web UI')
  eq('hero no creds', V2rayA.heroLine({ needsCredentials: true }), 'Set v2rayA login in widget settings')
  eq('hero checking', V2rayA.heroLine({}), 'Checking…')
/* ---- formatSpeed / formatBytes ---- */
eq('speed zero', V2rayA.formatSpeed(0), '0 B/s')
eq('speed bytes', V2rayA.formatSpeed(1023), '1023 B/s')
eq('speed kb', V2rayA.formatSpeed(1024), '1.0 KB/s')
eq('speed mb', V2rayA.formatSpeed(1578576), '1.5 MB/s')
eq('speed gb', V2rayA.formatSpeed(2.5 * 1073741824), '2.50 GB/s')
eq('bytes zero', V2rayA.formatBytes(0), '0 B')
eq('bytes mb', V2rayA.formatBytes(3 * 1048576), '3.0 MB')
}
