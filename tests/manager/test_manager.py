"""Manager tests (stdlib unittest, no network).

    python3 -m unittest discover -s tests/manager -v

With a real core available (OMARCHY_XRAY_TEST_BIN=/path/to/xray, or `xray`
on PATH) every generated config is also fed to `xray run -test`, so the
suite proves the core accepts what the parsers produce. Geo presets are
exercised when geoip.dat/geosite.dat sit next to that binary.
"""
import base64
import contextlib
import io
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[2]
MANAGER = ROOT / "bin" / "omarchy-xray"


def load_manager():
    loader = importlib.machinery.SourceFileLoader("omarchy_xray", str(MANAGER))
    spec = importlib.util.spec_from_loader("omarchy_xray", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


M = load_manager()
XRAY_BIN = os.environ.get("OMARCHY_XRAY_TEST_BIN") or shutil.which("xray") or ""
HAVE_XRAY = bool(XRAY_BIN) and os.path.isfile(XRAY_BIN)
UUID = "b831381d-6324-4d53-ad4f-8cda48b30811"
PBK = "mU8UUz4MfQIdXZiYkCo_HOl7M25S8CFYRUZTR0Y8pwc"
# `xray vlessenc` X25519 variant (VLESS encryption: allowed without TLS)
MLKEM_X25519 = "mlkem768x25519plus.native.0rtt.0n4CIx0Usp9ZnSUrbes7lfZvR16k6A6x0VcXV-gULWY"


def _xray_out(*args):
    return subprocess.run([XRAY_BIN, *args], capture_output=True, text=True).stdout


def mlkem_encryption():
    if HAVE_XRAY:
        for line in _xray_out("vlessenc").splitlines():
            if '"encryption"' in line:
                last = line.split('": "', 1)[1].rstrip('"')
        return last
    return "mlkem768x25519plus.native.0rtt." + "A" * 1580


def mldsa_verify():
    if HAVE_XRAY:
        for line in _xray_out("mldsa65").splitlines():
            if line.startswith("Verify:"):
                return line.split(":", 1)[1].strip()
    return "B" * 2600


def q(**kw):
    return urllib.parse.urlencode(kw, quote_via=urllib.parse.quote, safe="")


LINKS = {
    "vless-reality-vision": "vless://%s@example.com:443?%s#R%%C3%%A9ality" % (UUID, q(
        type="tcp", security="reality", pbk=PBK, sid="ab12", sni="www.microsoft.com",
        fp="chrome", flow="xtls-rprx-vision", spx="/")),
    "vless-ws-tls": "vless://%s@cdn.example.com:443?%s#WS" % (UUID, q(
        type="ws", path="/ws?ed=2048", host="cdn.example.com", security="tls",
        sni="cdn.example.com", alpn="h2,http/1.1", fp="firefox")),
    "vless-grpc-multi": "vless://%s@g.example.com:443?%s#GRPC" % (UUID, q(
        type="grpc", serviceName="gs", mode="multi", authority="a.example.com",
        security="tls", sni="g.example.com")),
    "vless-xhttp-reality": "vless://%s@x.example.com:443?%s#XHTTP" % (UUID, q(
        type="xhttp", mode="packet-up", path="/x", security="reality", pbk=PBK,
        sid="01", sni="www.apple.com",
        extra=json.dumps({"xPaddingBytes": "100-1000", "noGRPCHeader": False}))),
    "vless-httpupgrade": "vless://%s@h.example.com:443?%s#HU" % (UUID, q(
        type="httpupgrade", path="/hu", host="h.example.com", security="tls")),
    "vless-kcp-seed-header": "vless://%s@k.example.com:1234?%s#KCP" % (UUID, q(
        type="kcp", seed="s3cr3t", headerType="srtp", encryption=MLKEM_X25519)),
    "vless-kcp-plain": "vless://%s@192.168.1.10:1234?%s#KCP2" % (UUID, q(type="kcp")),
    "vmess-raw-http": "vmess://" + base64.b64encode(json.dumps({
        "v": "2", "ps": "TCPHTTP", "add": "t.example.com", "port": "80", "id": UUID,
        "net": "tcp", "type": "http", "host": "t.example.com", "path": "/a,/b",
        "tls": ""}).encode()).decode(),
    "vless-ipv6": "vless://%s@[2001:db8::1]:8443?%s#V6" % (UUID, q(
        type="tcp", security="tls", sni="v6.example.com")),
    "vmess-ws": "vmess://" + base64.b64encode(json.dumps({
        "v": "2", "ps": "VMess WS", "add": "vm.example.com", "port": "443", "id": UUID,
        "aid": "0", "scy": "auto", "net": "ws", "type": "none", "host": "vm.example.com",
        "path": "/vm", "tls": "tls", "sni": "vm.example.com", "alpn": "http/1.1",
        "fp": "chrome"}).encode()).decode(),
    "vmess-grpc": "vmess://" + base64.urlsafe_b64encode(json.dumps({
        "v": "2", "ps": "VMess gRPC", "add": "1.2.3.4", "port": 2053, "id": UUID,
        "net": "grpc", "type": "multi", "path": "svc", "tls": "tls",
        "sni": "vg.example.com"}).encode()).decode().rstrip("="),
    "trojan-ws": "trojan://p%%40ss%%3Aword@tr.example.com:443?%s#Trojan" % q(
        type="ws", path="/tr", security="tls", sni="tr.example.com"),
    "trojan-reality": "trojan://secret@tr2.example.com:443?%s#TrojanR" % q(
        security="reality", pbk=PBK, sid="", sni="www.cloudflare.com", type="tcp"),
    "ss-sip002": "ss://%s@ss.example.com:8388#SS" % base64.urlsafe_b64encode(
        b"aes-256-gcm:hunter2").decode().rstrip("="),
    "ss-2022": "ss://%s@ss2.example.com:8389#SS2022" % urllib.parse.quote(
        "2022-blake3-aes-128-gcm:" + base64.b64encode(b"0123456789abcdef").decode(), safe=""),
    "ss-legacy": "ss://%s#Legacy" % base64.b64encode(
        b"chacha20-ietf-poly1305:pw@ss3.example.com:8390").decode(),
    "hy2-obfs": "hysteria2://auth%%3Atoken@hy.example.com:443/?%s#HY2" % q(
        sni="hy.example.com", obfs="salamander", **{"obfs-password": "gecko"},
        pinSHA256="AB" * 32),
    "hy2-hop": "hy2://tok@hy2.example.com:443,20000-30000?%s#HOP" % q(insecure="1"),
}

SKIPPED = {
    "h2": "vless://%s@a.example.com:443?type=h2&security=tls#H2" % UUID,
    "http": "vless://%s@a.example.com:443?type=http&security=tls#HTTP" % UUID,
    "quic": "vless://%s@a.example.com:443?type=quic#QUIC" % UUID,
    "ws-reality": "vless://%s@a.example.com:443?type=ws&security=reality&pbk=%s#X" % (UUID, PBK),
    "ss-plugin": "ss://%s@a.example.com:8388?plugin=obfs-local#P" % base64.b64encode(
        b"aes-128-gcm:x").decode(),
    "socks": "socks://a.example.com:1080",
    "vless-plain-public": "vless://%s@a.example.com:80?type=ws&security=none#P" % UUID,
    "trojan-plain-public": "trojan://pw@a.example.com:80?security=none#P",
}


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="oxtest-"))
        self._saved = {k: getattr(M, k) for k in (
            "CFG", "CONF", "STATE", "LAT", "CUSTOM", "UNIT_DIR", "UNIT", "T2S_UNIT",
            "XRAY", "default_dev", "bootstrap_dns", "running_units", "apply_system_proxy",
            "core_version")}
        self.proxy_calls = []
        M.apply_system_proxy = lambda st, on: self.proxy_calls.append(on)   # never the real gsettings
        M.CFG = self.tmp / "cfg"
        M.CONF = M.CFG / "config.json"
        M.STATE = M.CFG / "state.json"
        M.LAT = M.CFG / "latency.json"
        M.CUSTOM = M.CFG / "custom.json"
        M.UNIT_DIR = self.tmp / "units"
        M.UNIT = M.UNIT_DIR / M.SERVICE
        M.T2S_UNIT = M.UNIT_DIR / M.T2S_SERVICE
        M.XRAY = XRAY_BIN if HAVE_XRAY else str(self.tmp / "no-xray")
        M.default_dev = lambda: "wlan0"
        M.core_version = lambda: None    # link policy as for an unknown (= latest) core
        M.bootstrap_dns = lambda custom: ["192.168.1.1", "1.1.1.1"]
        self._env = os.environ.get("XRAY_LOCATION_ASSET")
        if HAVE_XRAY:
            os.environ["XRAY_LOCATION_ASSET"] = os.path.dirname(os.path.realpath(XRAY_BIN))
        os.environ["XDG_RUNTIME_DIR"] = str(self.tmp)

    def tearDown(self):
        for k, v in self._saved.items():
            setattr(M, k, v)
        if self._env is None:
            os.environ.pop("XRAY_LOCATION_ASSET", None)
        else:
            os.environ["XRAY_LOCATION_ASSET"] = self._env
        shutil.rmtree(self.tmp, ignore_errors=True)

    def node(self, key):
        n = M.parse_link(LINKS[key])
        n["sub"] = 0
        n["id"] = M.node_id(n["ob"])
        return n

    def state(self, nodes, **kw):
        st = {"subs": [{"url": "https://sub.example.com/x"}], "nodes": nodes,
              "selected": nodes[0]["id"], "mode": "proxy", "routing": "global",
              "adblock": False, "skipped": {}}
        st.update(kw)
        return st

    def assertCoreAccepts(self, conf):
        if not HAVE_XRAY:
            self.skipTest("no xray core (set OMARCHY_XRAY_TEST_BIN)")
        err = M.xray_test_config(conf)
        self.assertEqual(err, "", "xray rejected config: " + err)


class LinkParsing(Base):
    def test_all_links_parse(self):
        for key, link in LINKS.items():
            with self.subTest(key=key):
                n = M.parse_link(link)
                self.assertIn(n["proto"], M.PROTOCOLS)
                self.assertTrue(n["name"])

    def test_vless_reality(self):
        n = self.node("vless-reality-vision")
        self.assertEqual(n["name"], "Réality")
        user = n["ob"]["settings"]["vnext"][0]["users"][0]
        self.assertEqual(user, {"id": UUID, "encryption": "none", "flow": "xtls-rprx-vision"})
        r = n["ob"]["streamSettings"]["realitySettings"]
        self.assertEqual(r["publicKey"], PBK)
        self.assertEqual(r["spiderX"], "/")          # from spx, not from path
        self.assertEqual(r["serverName"], "www.microsoft.com")

    def test_ws_host_and_early_data(self):
        s = self.node("vless-ws-tls")["ob"]["streamSettings"]
        self.assertEqual(s["wsSettings"], {"path": "/ws?ed=2048", "host": "cdn.example.com"})
        self.assertEqual(s["tlsSettings"]["alpn"], ["h2", "http/1.1"])
        self.assertEqual(s["tlsSettings"]["fingerprint"], "firefox")

    def test_grpc_multi_authority(self):
        g = self.node("vless-grpc-multi")["ob"]["streamSettings"]["grpcSettings"]
        self.assertEqual(g, {"serviceName": "gs", "multiMode": True, "authority": "a.example.com"})

    def test_xhttp_extra(self):
        s = self.node("vless-xhttp-reality")["ob"]["streamSettings"]
        self.assertEqual(s["network"], "xhttp")
        self.assertEqual(s["xhttpSettings"]["mode"], "packet-up")
        self.assertEqual(s["xhttpSettings"]["extra"]["xPaddingBytes"], "100-1000")

    def test_kcp_masks(self):
        fm = self.node("vless-kcp-seed-header")["ob"]["streamSettings"]["finalmask"]["udp"]
        self.assertEqual(fm[0], {"type": "mkcp-legacy", "settings": {"value": "s3cr3t"}})
        self.assertEqual(fm[1], {"type": "mkcp-legacy", "settings": {"header": "srtp"}})
        plain = self.node("vless-kcp-plain")["ob"]["streamSettings"]["finalmask"]["udp"]
        self.assertEqual(plain, [{"type": "mkcp-legacy"}])

    def test_raw_http_header(self):
        h = self.node("vmess-raw-http")["ob"]["streamSettings"]["rawSettings"]["header"]
        self.assertEqual(h["request"]["path"], ["/a", "/b"])
        self.assertEqual(h["request"]["headers"]["Host"], ["t.example.com"])

    def test_ipv6_host(self):
        n = self.node("vless-ipv6")
        self.assertEqual(n["host"], "2001:db8::1")
        self.assertEqual(M.addr_label(n["host"], n["port"]), "[2001:db8::1]:8443")

    def test_plus_is_not_space(self):
        n = M.parse_link("vless://%s@a.example.com:443?encryption=a+b%%2Bc&type=tcp#x" % UUID)
        self.assertEqual(n["ob"]["settings"]["vnext"][0]["users"][0]["encryption"], "a+b+c")

    def test_mlkem_encryption_and_pqv(self):
        enc, pqv = mlkem_encryption(), mldsa_verify()
        self.assertGreater(len(enc), 1000)
        link = "vless://%s@a.example.com:443?%s#PQ" % (UUID, q(
            encryption=enc, security="reality", pbk=PBK, sni="www.apple.com", pqv=pqv,
            type="tcp", flow="xtls-rprx-vision"))
        n = M.parse_link(link)
        self.assertEqual(n["ob"]["settings"]["vnext"][0]["users"][0]["encryption"], enc)
        self.assertEqual(n["ob"]["streamSettings"]["realitySettings"]["mldsa65Verify"], pqv)
        n["id"] = M.node_id(n["ob"])
        self.assertCoreAccepts(M.build_config(self.state([n])))

    def test_vmess(self):
        n = self.node("vmess-ws")
        self.assertEqual(n["ob"]["settings"]["vnext"][0]["users"][0]["security"], "auto")
        self.assertEqual(n["ob"]["streamSettings"]["wsSettings"]["path"], "/vm")
        g = self.node("vmess-grpc")["ob"]["streamSettings"]
        self.assertEqual(g["grpcSettings"]["serviceName"], "svc")
        self.assertTrue(g["grpcSettings"]["multiMode"])
        self.assertNotIn("serverName", {} if "tlsSettings" not in g else {})

    def test_trojan_password_decoding(self):
        srv = self.node("trojan-ws")["ob"]["settings"]["servers"][0]
        self.assertEqual(srv["password"], "p@ss:word")

    def test_shadowsocks_forms(self):
        a = self.node("ss-sip002")["ob"]["settings"]["servers"][0]
        self.assertEqual((a["method"], a["password"]), ("aes-256-gcm", "hunter2"))
        b = self.node("ss-2022")["ob"]["settings"]["servers"][0]
        self.assertEqual(b["method"], "2022-blake3-aes-128-gcm")
        c = self.node("ss-legacy")["ob"]["settings"]["servers"][0]
        self.assertEqual((c["method"], c["address"]), ("chacha20-poly1305", "ss3.example.com"))

    def test_hysteria2(self):
        n = self.node("hy2-obfs")
        s = n["ob"]["streamSettings"]
        self.assertEqual(n["ob"]["settings"], {"version": 2, "address": "hy.example.com", "port": 443})
        self.assertEqual(s["hysteriaSettings"], {"version": 2, "auth": "auth:token"})
        self.assertEqual(s["finalmask"]["udp"][0]["type"], "salamander")
        self.assertEqual(s["tlsSettings"]["pinnedPeerCertSha256"], "ab" * 32)
        self.assertEqual(s["tlsSettings"]["alpn"], ["h3"])
        self.assertNotIn("fingerprint", s["tlsSettings"])
        self.assertEqual(self.node("hy2-hop")["port"], 443)

    def test_skip_reasons(self):
        for key, link in SKIPPED.items():
            with self.subTest(key=key):
                with self.assertRaises(M.Skip):
                    M.parse_link(link)
        with self.assertRaises(M.Skip) as cm:
            M.parse_link(SKIPPED["h2"])
        self.assertIn("removed from Xray core", str(cm.exception))

    def test_plain_policy_follows_core_version(self):
        link = SKIPPED["vless-plain-public"]
        M.core_version = lambda: (26, 6, 27)            # before the core refused it
        self.assertEqual(M.parse_link(link)["sec"], "none")
        M.core_version = lambda: (26, 7, 11)
        with self.assertRaises(M.Skip):
            M.parse_link(link)

    def test_unknown_fingerprint_falls_back(self):
        n = M.parse_link("vless://%s@a.example.com:443?security=tls&fp=bogus#x" % UUID)
        self.assertEqual(n["ob"]["streamSettings"]["tlsSettings"]["fingerprint"], "chrome")

    def test_bounds(self):
        with self.assertRaises(ValueError):
            M.parse_link("vless://%s@a.example.com:443?%s" % (UUID, "&".join(
                "k%d=v" % i for i in range(80))))
        with self.assertRaises(ValueError):
            M.parse_link("vless://bad%20id@a.example.com:443")
        with self.assertRaises(ValueError):
            M.parse_link("vless://%s@exa mple.com:443" % UUID)

    def test_every_link_accepted_by_core(self):
        nodes = []
        for key in LINKS:
            n = self.node(key)
            nodes.append(n)
        for n in nodes:
            with self.subTest(node=n["name"]):
                self.assertCoreAccepts(M.build_config(self.state([n], selected=n["id"])))


class Subscriptions(Base):
    def body_links(self):
        return "\n".join(LINKS.values()) + "\n" + "\n".join(SKIPPED.values())

    def test_plain_text(self):
        skipped = {}
        nodes = M.nodes_from_body(self.body_links().encode(), 0, skipped)
        self.assertEqual(len(nodes), len(LINKS))
        self.assertEqual(sum(skipped.values()), len(SKIPPED))

    def test_base64_variants(self):
        raw = self.body_links().encode()
        for enc in (base64.b64encode(raw), base64.urlsafe_b64encode(raw).rstrip(b"="),
                    base64.encodebytes(raw)):
            with self.subTest(enc=enc[:10]):
                self.assertEqual(len(M.nodes_from_body(enc, 0, {})), len(LINKS))

    def test_json_subscription(self):
        body = json.dumps([
            {"remarks": "JSON node", "outbounds": [
                {"tag": "proxy", "protocol": "vless",
                 "settings": {"vnext": [{"address": "j.example.com", "port": 443,
                                         "users": [{"id": UUID, "encryption": "none"}]}]},
                 "streamSettings": {"network": "xhttp", "security": "tls",
                                    "xhttpSettings": {"path": "/j"},
                                    "sockopt": {"dialerProxy": "fragment"}}},
                {"tag": "direct", "protocol": "freedom"}]},
            {"remarks": "no proxy", "outbounds": [{"protocol": "freedom"}]},
        ]).encode()
        skipped = {}
        nodes = M.nodes_from_body(body, 0, skipped)
        self.assertEqual(len(nodes), 1)
        self.assertEqual(nodes[0]["name"], "JSON node")
        self.assertNotIn("tag", nodes[0]["ob"])
        self.assertNotIn("dialerProxy", nodes[0]["ob"]["streamSettings"]["sockopt"])
        self.assertEqual(sum(skipped.values()), 1)

    def test_headers(self):
        self.assertEqual(M.parse_userinfo("upload=10; download=20; total=100; expire=1700000000"),
                         {"upload": 10, "download": 20, "total": 100, "expire": 1700000000})
        self.assertEqual(M.parse_title("base64:" + base64.b64encode("Мой VPN".encode()).decode()),
                         "Мой VPN")
        self.assertEqual(M.parse_interval("12"), 12)
        self.assertEqual(M.parse_interval("nope"), 0)

    def test_stable_ids_keep_selection(self):
        a, b = self.node("vless-ws-tls"), self.node("trojan-ws")
        st = self.state([a, b], selected=b["id"])
        again = [self.node("trojan-ws"), self.node("vless-ws-tls")]   # order changed
        st["nodes"] = again
        M.resolve_selection(st, b["id"], b["name"])
        self.assertEqual(st["selected"], b["id"])
        st["nodes"] = [a]
        M.resolve_selection(st, "n0", "")                      # v2 index selection
        self.assertEqual(st["selected"], a["id"])

    def test_core_filter_drops_rejected(self):
        if not HAVE_XRAY:
            self.skipTest("no xray core")
        good = self.node("vless-ws-tls")
        bad = self.node("trojan-ws")
        bad["ob"]["streamSettings"]["tlsSettings"]["allowInsecure"] = True   # removed in core
        skipped = {}
        kept = M.core_filter([good, bad, self.node("ss-sip002")], skipped)
        self.assertEqual([n["name"] for n in kept], ["WS", "SS"])
        self.assertEqual(skipped, {"rejected by xray core": 1})


class ConfigBuilding(Base):
    def nodes(self):
        return [self.node(k) for k in LINKS]

    def test_only_selected_outbound(self):
        ns = self.nodes()
        conf = M.build_config(self.state(ns, selected=ns[3]["id"]))
        proxies = [o for o in conf["outbounds"] if o["protocol"] in M.PROTOCOLS]
        self.assertEqual(len(proxies), 1)
        self.assertEqual(proxies[0]["tag"], "proxy")
        self.assertEqual(conf["metrics"], {"listen": "127.0.0.1:%d" % M.METRICS})
        self.assertCoreAccepts(conf)

    def test_tun_config(self):
        ns = self.nodes()
        conf = M.build_config(self.state(ns, mode="tun"), {"outbounds": [
            {"tag": "frag", "protocol": "freedom"}]})
        # xray never opens the device: tun2socks feeds socks-in
        self.assertNotIn("tun", [i["protocol"] for i in conf["inbounds"]])
        self.assertFalse(conf["inbounds"][0]["sniffing"]["routeOnly"])
        self.assertEqual(conf["routing"]["rules"][0],
                         {"inboundTag": ["socks-in"], "port": "53", "outboundTag": "dns-out"})
        # every connection xray makes is bound to the physical link (no loop)
        for ob in conf["outbounds"]:
            if ob["protocol"] != "blackhole":
                self.assertEqual(ob["streamSettings"]["sockopt"]["interface"], "wlan0", ob["tag"])
        proxy = conf["outbounds"][0]
        self.assertEqual(proxy["streamSettings"]["sockopt"]["domainStrategy"], "UseIPv4v6")
        boot = [s for s in conf["dns"]["servers"] if isinstance(s, dict)]
        self.assertTrue(all(s["tag"] == "dns-bootstrap" for s in boot))
        self.assertIn("full:" + ns[0]["host"], boot[0]["domains"])
        self.assertCoreAccepts(conf)

    def test_tun_interface_fallback(self):
        ns = self.nodes()
        M.default_dev = lambda: None
        with self.assertRaises(SystemExit):              # offline, nothing bound yet
            M.build_config(self.state(ns, mode="tun"))
        M.CFG.mkdir(parents=True, exist_ok=True)
        M.CONF.write_text(json.dumps({"outbounds": [
            {"tag": "direct", "streamSettings": {"sockopt": {"interface": "eth0"}}}]}))
        conf = M.build_config(self.state(ns, mode="tun"))  # offline: keep the last link
        self.assertEqual(conf["outbounds"][0]["streamSettings"]["sockopt"]["interface"], "eth0")
        proxy = M.build_config(self.state(ns))
        self.assertNotIn("interface", json.dumps(proxy))

    def test_dns_preset_reaches_the_tun_config(self):
        ns = self.nodes()
        M.CFG.mkdir(parents=True, exist_ok=True)
        M.CONF.write_text(json.dumps({"outbounds": [
            {"tag": "direct", "streamSettings": {"sockopt": {"interface": "eth0"}}}]}))
        for name, url in M.DNS_PRESETS.items():
            if url is None:
                continue
            with self.subTest(dns=name):
                conf = M.build_config(self.state(ns, mode="tun", dns=name))
                self.assertEqual(conf["dns"]["servers"][-1], url)
        conf = M.build_config(self.state(ns, mode="tun"))       # older state: no key
        self.assertEqual(conf["dns"]["servers"][-1], M.DNS_PRESETS["cloudflare"])
        sysconf = M.build_config(self.state(ns, mode="tun", dns="system"), {"bootstrapDns": ["192.168.1.1"]})
        self.assertIn("192.168.1.1", sysconf["dns"]["servers"])
        self.assertIn({"inboundTag": ["dns-internal"], "outboundTag": "direct"}, sysconf["routing"]["rules"])
        with self.assertRaises(SystemExit):
            M.cmd_dns("evil.example")

    def test_rebind_follows_default_route(self):
        if not HAVE_XRAY:
            self.skipTest("no xray core")
        st = self.state(self.nodes(), mode="tun")
        M.CFG.mkdir(parents=True, exist_ok=True)
        M.STATE.write_text(json.dumps(st))
        M.write_config(M.load_state())
        calls = []
        saved = M.uctl
        M.uctl = lambda *a, **k: calls.append(a)
        try:
            self.assertFalse(M._rebind())                   # still on wlan0
            M.default_dev = lambda: "eth0"
            self.assertTrue(M._rebind())
            self.assertEqual(M.bound_iface(), "eth0")
            self.assertEqual(calls, [("restart", M.SERVICE)])
        finally:
            M.uctl = saved

    def test_tun_every_protocol(self):
        for n in self.nodes():
            with self.subTest(node=n["name"]):
                self.assertCoreAccepts(M.build_config(self.state([n], mode="tun")))

    def test_auto_balancer(self):
        ns = self.nodes()
        st = self.state(ns, selected="auto")
        for mode in ("proxy", "tun"):
            with self.subTest(mode=mode):
                st["mode"] = mode
                conf = M.build_config(st)
                self.assertEqual(conf["routing"]["balancers"][0]["strategy"]["type"], "leastPing")
                self.assertEqual(conf["routing"]["rules"][-1]["balancerTag"], "auto")
                self.assertIn("observatory", conf)
                tags = [o["tag"] for o in conf["outbounds"] if o["tag"].startswith("node-")]
                self.assertEqual(len(tags), min(len(ns), M.AUTO_MAX))
                self.assertCoreAccepts(conf)

    def test_routing_presets(self):
        ns = self.nodes()
        for cc, (_, tlds, site) in M.REGIONS.items():
            conf = M.build_config(self.state(ns, routing=cc + "-direct", adblock=True))
            flat = json.dumps(conf["routing"]["rules"])
            for t in tlds:
                self.assertIn("domain:" + t, flat)
            if M.asset_dir():
                self.assertIn("geosite:category-ads-all", flat)
                self.assertIn("geoip:" + cc, flat)
                if site:
                    self.assertIn("geosite:" + site, flat)
                self.assertEqual(conf["routing"]["domainStrategy"], "IPIfNonMatch")
            self.assertCoreAccepts(conf)
        conf = M.build_config(self.state(ns, routing="global"))
        self.assertNotIn("geoip:ru", json.dumps(conf["routing"]["rules"]))

    def test_region_validation(self):
        self.assertEqual(M.region_of("kz-direct"), "kz")
        for bad in ("global", "xx-direct", "de-direct", "ru", "RU-direct", "", None):
            self.assertIsNone(M.region_of(bad), bad)
        with self.assertRaises(SystemExit):
            M.cmd_routing("xx-direct")
        M.CFG.mkdir(parents=True, exist_ok=True)
        for routing, want in (("kz-direct", "kz-direct"), ("ru-direct", "ru-direct"),
                              ("xx-direct", "global")):
            M.STATE.write_text(json.dumps(self.state(self.nodes(), routing=routing)))
            self.assertEqual(M.load_state()["routing"], want)

    def test_custom_json(self):
        ns = self.nodes()
        custom = {
            "routing": {"rules": [{"domain": ["domain:example.org"], "outboundTag": "direct"}]},
            "dns": {"servers": ["8.8.8.8"], "queryStrategy": "UseIPv4"},
            "outbounds": [{"tag": "fragment", "protocol": "freedom",
                           "settings": {"fragment": {"packets": "tlshello", "length": "100-200",
                                                     "interval": "10-20"}}}],
            "proxyPatch": {"mux": {"enabled": False},
                           "streamSettings": {"sockopt": {"tcpFastOpen": True}}},
            "log": {"loglevel": "info"},
            "_comment": "ignored",
        }
        conf = M.build_config(self.state(ns, mode="tun", selected=ns[1]["id"]), custom)
        self.assertEqual(conf["log"]["loglevel"], "info")
        self.assertNotIn("_comment", conf)
        self.assertEqual(conf["dns"]["servers"][0], "8.8.8.8")
        self.assertEqual(conf["dns"]["queryStrategy"], "UseIPv4")
        self.assertIn({"domain": ["domain:example.org"], "outboundTag": "direct"},
                      conf["routing"]["rules"])
        self.assertTrue(conf["outbounds"][0]["streamSettings"]["sockopt"]["tcpFastOpen"])
        self.assertEqual(conf["outbounds"][-1]["tag"], "fragment")
        self.assertCoreAccepts(conf)

    def test_custom_reserved_tag(self):
        with self.assertRaises(SystemExit):
            M.build_config(self.state(self.nodes()), {"outbounds": [{"tag": "proxy"}]})

    def test_write_config_refuses_bad_config(self):
        if not HAVE_XRAY:
            self.skipTest("no xray core")
        st = self.state(self.nodes())
        M.write_config(st)
        before = M.CONF.read_text()
        M.CUSTOM.write_text(json.dumps({"routing": {"rules": [{"outboundTag": "nope"}]}}))
        with self.assertRaises(SystemExit):
            M.write_config(st)
        self.assertEqual(M.CONF.read_text(), before)


class TunInstall(Base):
    def test_unit_text(self):
        t = M.tun_unit_text(1000, "/usr/bin/ip", "/usr/bin/udevadm", "/usr/bin/resolvectl")
        self.assertIn(M.TUN_LAYOUT + "\n", t)
        self.assertIn("Type=oneshot\n", t)
        self.assertIn("ExecStart=/usr/bin/ip tuntap add dev xray0 mode tun user 1000\n", t)
        self.assertIn("ExecStart=/usr/bin/ip route add default dev xray0 table 18180\n", t)
        self.assertIn("ExecStart=/usr/bin/ip rule add pref 18180 lookup main suppress_prefixlength 0\n", t)
        self.assertIn("ExecStart=/usr/bin/ip rule add pref 18181 from 0.0.0.0/32 lookup 18180\n", t)
        self.assertIn("ExecStart=/usr/bin/ip rule add pref 18182 from 198.18.0.1 lookup 18180\n", t)
        self.assertIn("ExecStart=-/usr/bin/ip -6 rule add pref 18181 from fdfe:dcba:9876::1 lookup 18180\n", t)
        self.assertIn("ExecStart=-/usr/bin/resolvectl dns xray0 198.18.0.2\n", t)
        # ownership: only an xray0 with our alias is ever deleted, rules only by
        # their full spec, and a foreign xray0 stops the start
        self.assertIn("ExecStart=/usr/bin/ip link set dev xray0 alias omarchy-xray\n", t)
        for key in ("ExecStartPre", "ExecStopPost"):
            self.assertIn("%s=-/bin/sh -c \"/usr/bin/ip link show dev xray0 2>/dev/null | grep -q "
                          "'alias omarchy-xray' && exec /usr/bin/ip link delete xray0\"\n" % key, t)
            self.assertIn("%s=-/usr/bin/ip rule delete pref 18181 from 0.0.0.0/32 lookup 18180\n" % key, t)
            self.assertIn("%s=-/usr/bin/ip -6 rule delete pref 18180 lookup main suppress_prefixlength 0\n" % key, t)
            self.assertNotIn("%s=-/usr/bin/ip link delete xray0\n" % key, t)
        self.assertEqual(t.count("ExecStartPre="), 7)
        self.assertEqual(t.count("ExecStopPost="), 6)
        self.assertIn("then echo 'xray0 exists and is not ours - refusing' >&2; exit 1; fi", t)
        self.assertIn("CapabilityBoundingSet=CAP_NET_ADMIN\n", t)
        self.assertNotIn("User=", t)
        self.assertNotIn("Ambient", t)
        # root runs nothing but these system tools (sh only to wrap ip)
        for line in t.splitlines():
            if line.startswith("Exec"):
                cmd = line.split("=", 1)[1].lstrip("-")
                self.assertIn(cmd.split()[0], ("/usr/bin/ip", "/usr/bin/udevadm", "/usr/bin/resolvectl", "/bin/sh"))
                if cmd.startswith("/bin/sh"):
                    self.assertNotIn("omarchy-xray ", cmd.replace("alias omarchy-xray", ""))

    def test_t2s_unit_text(self):
        t = M.t2s_unit_text()
        # the root unit is started/stopped only through the ownership check
        self.assertIn("ExecStartPre=%s tun-unit start\n" % M.SELF, t)
        self.assertIn("ExecStart=%s tun-run\n" % M.SELF, t)
        # kill switch: only a successful (deliberate) stop removes the device
        self.assertIn("ExecStopPost=-/bin/sh -c '[ \"$$SERVICE_RESULT\" = success ] && exec %s "
                      "tun-unit stop'\n" % M.SELF, t)
        self.assertNotIn(M.SYSTEMCTL, t)
        self.assertIn("NoNewPrivileges=true\n", t)

    def test_polkit_rule_scope(self):
        r = M.polkit_rule_text("alice")
        self.assertIn('subject.user === "alice"', r)
        self.assertIn('action.lookup("unit") === "omarchy-xray-tun.service"', r)
        self.assertIn('verb === "start" || verb === "stop" || verb === "restart"', r)
        self.assertNotIn("manage-unit-files", r)

    def test_user_name_validation(self):
        self.assertTrue(M._USER_RE.match("alice"))
        for bad in ("Alice", "a b", "root;x", "x$", "-x"):
            self.assertFalse(M._USER_RE.match(bad), bad)
        self.assertFalse(M._UNIT_PATH_RE.match("/home/a b/x"))

    def test_install_refuses_without_root(self):
        if os.geteuid() == 0:
            self.skipTest("running as root")
        with self.assertRaises(SystemExit):
            M.cmd_tun_install()

    def test_installed_with_unreadable_polkit_dir(self):
        # /etc/polkit-1/rules.d is root:polkitd 0750: users cannot stat the rule
        if os.geteuid() == 0:
            self.skipTest("running as root")
        saved = M.SYS_UNIT, M.POLKIT_RULE
        rules = self.tmp / "rules.d"
        rules.mkdir()
        (rules / "49-omarchy-xray.rules").write_text("//\n")
        os.chmod(rules, 0o000)
        M.SYS_UNIT, M.POLKIT_RULE = self.tmp / "unit.service", rules / "49-omarchy-xray.rules"
        M.SYS_UNIT.write_text("[Unit]\n")          # v3.0 layout: xray with caps
        try:
            self.assertFalse(M.tun_installed())
            M.SYS_UNIT.write_text(M.TUN_LAYOUT + "\n[Unit]\n")
            self.assertTrue(M.tun_installed())
        finally:
            os.chmod(rules, 0o755)
            M.SYS_UNIT, M.POLKIT_RULE = saved


class TunOwnership(Base):
    """tun-install/tun-uninstall touch only what they wrote for this user."""

    def setUp(self):
        super().setUp()
        saved = {k: getattr(M, k) for k in ("SYS_UNIT", "POLKIT_RULE", "NETWORKD_FILE",
                                              "TUN_RECORD", "ROOT", "sh")}
        self.addCleanup(lambda: [setattr(M, k, v) for k, v in saved.items()])
        etc = self.tmp / "etc"
        M.SYS_UNIT = etc / "system" / M.TUN_SERVICE
        M.POLKIT_RULE = etc / "rules.d" / "49-omarchy-xray.rules"
        M.NETWORKD_FILE = etc / "network" / "10-omarchy-xray.network"
        M.TUN_RECORD = self.tmp / "var" / "tun-install.json"
        M.ROOT = os.getuid()                       # "root" is us: the files stay in tmp
        self.calls = []
        self.loaded = None                         # override what systemd has loaded
        self.active = False                        # is-active answer for the root unit

        def fake_sh(*cmd, **kw):                   # never touch the real systemd
            self.calls.append(cmd)
            if "show" in cmd:
                props = self.loaded or (
                    {"LoadState": "loaded", "ActiveState": "active", "FragmentPath": str(M.SYS_UNIT)}
                    if M.SYS_UNIT.exists() else {"LoadState": "not-found", "ActiveState": "inactive"})
                props = {"FragmentPath": "", "DropInPaths": "", **props}
                return subprocess.CompletedProcess(
                    cmd, 0, "".join("%s=%s\n" % kv for kv in props.items()), "")
            if "is-active" in cmd and M.TUN_SERVICE in cmd:
                return subprocess.CompletedProcess(cmd, 0, "active\n" if self.active else "inactive\n", "")
            return subprocess.CompletedProcess(cmd, 0, "inactive\n", "")
        M.sh = fake_sh
        os.environ["SUDO_UID"] = str(os.getuid())
        self.addCleanup(os.environ.pop, "SUDO_UID", None)
        chown = unittest.mock.patch("os.chown")
        chown.start()
        self.addCleanup(chown.stop)

    def run_json(self, fn):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            fn()
        return json.loads(buf.getvalue().strip().splitlines()[-1])

    def stops(self):
        return [c for c in self.calls if "stop" in c]

    def root_unit_stops(self):
        return [c for c in self.calls if "stop" in c and M.TUN_SERVICE in c]

    def test_install_records_what_it_wrote_and_reinstalls(self):
        self.run_json(M.cmd_tun_install)
        rec = json.loads(M.TUN_RECORD.read_text())
        self.assertEqual(rec["uid"], os.getuid())
        for path in (M.SYS_UNIT, M.POLKIT_RULE):
            self.assertEqual(rec["files"][str(path)], M._sha(path.read_text()))
        self.assertFalse(M.NETWORKD_FILE.exists())         # networkd inactive
        self.run_json(M.cmd_tun_install)                    # ours: replaced again
        self.assertEqual(len(self.stops()), 1)              # nothing loaded the first time

    def test_install_refuses_foreign_changed_or_linked_files(self):
        M.SYS_UNIT.parent.mkdir(parents=True)
        M.SYS_UNIT.write_text("[Service]\nExecStart=/usr/bin/true\n")   # someone else's unit
        with self.assertRaises(SystemExit):
            self.run_json(M.cmd_tun_install)
        self.assertEqual(M.SYS_UNIT.read_text(), "[Service]\nExecStart=/usr/bin/true\n")
        self.assertFalse(M.TUN_RECORD.exists())
        self.assertEqual(self.stops(), [])                  # not even stopped
        M.SYS_UNIT.unlink()
        self.run_json(M.cmd_tun_install)
        M.POLKIT_RULE.write_text(M.POLKIT_RULE.read_text() + "// local edit\n")
        with self.assertRaises(SystemExit):
            self.run_json(M.cmd_tun_install)                 # changed since we wrote it
        self.assertTrue(M.POLKIT_RULE.read_text().endswith("// local edit\n"))
        M.POLKIT_RULE.unlink()
        M.POLKIT_RULE.symlink_to(self.tmp / "elsewhere")
        with self.assertRaises(SystemExit):
            self.run_json(M.cmd_tun_install)
        self.assertTrue(M.POLKIT_RULE.is_symlink())

    def test_another_users_setup_is_left_alone(self):
        self.run_json(M.cmd_tun_install)
        rec = json.loads(M.TUN_RECORD.read_text())
        rec["uid"] += 1
        M.TUN_RECORD.write_text(json.dumps(rec))
        before = M.SYS_UNIT.read_text()
        for fn in (M.cmd_tun_install, M.cmd_tun_uninstall):
            with self.subTest(fn=fn.__name__), self.assertRaises(SystemExit):
                self.run_json(fn)
        self.assertEqual(M.SYS_UNIT.read_text(), before)

    def test_uninstall_removes_only_what_is_ours(self):
        self.run_json(M.cmd_tun_install)
        M.NETWORKD_FILE.parent.mkdir(parents=True)
        M.NETWORKD_FILE.write_text("[Match]\nName=other0\n")          # not ours
        res = self.run_json(M.cmd_tun_uninstall)
        self.assertEqual(sorted(res["removed"]), sorted([str(M.SYS_UNIT), str(M.POLKIT_RULE)]))
        self.assertEqual(res["kept"], [str(M.NETWORKD_FILE)])
        self.assertTrue(M.NETWORKD_FILE.exists())
        self.assertFalse(M.TUN_RECORD.exists())

    def test_uninstall_refuses_a_foreign_unit(self):
        self.run_json(M.cmd_tun_install)
        M.SYS_UNIT.write_text("[Service]\nExecStart=/usr/bin/true\n")
        with self.assertRaises(SystemExit):
            self.run_json(M.cmd_tun_uninstall)
        self.assertTrue(M.SYS_UNIT.exists() and M.POLKIT_RULE.exists())
        self.assertEqual(self.stops(), [])                  # nothing was loaded at install

    def test_a_foreign_loaded_unit_is_never_stopped(self):
        # /etc/systemd/system has no unit, but systemd loaded one of that name
        # from elsewhere, or ours carries someone's drop-in: hands off.
        other = "/run/systemd/system/" + M.TUN_SERVICE
        cases = [
            {"LoadState": "loaded", "ActiveState": "active", "FragmentPath": other},
            {"LoadState": "loaded", "ActiveState": "active", "FragmentPath": ""},   # transient
            {"LoadState": "masked", "ActiveState": "inactive", "FragmentPath": "/dev/null"},
            {"LoadState": "not-found", "ActiveState": "active"},                    # file gone, running
            {"LoadState": "loaded", "ActiveState": "active", "FragmentPath": str(M.SYS_UNIT),
             "DropInPaths": "/etc/systemd/system/%s.d/x.conf" % M.TUN_SERVICE},
        ]
        for props in cases:
            with self.subTest(props=props):
                self.loaded = props
                with self.assertRaises(SystemExit):
                    self.run_json(M.cmd_tun_install)
                self.assertEqual(self.stops(), [])
                self.assertFalse(M.SYS_UNIT.exists() or M.TUN_RECORD.exists())
        self.loaded = None
        self.run_json(M.cmd_tun_install)
        self.loaded = cases[0]
        with self.assertRaises(SystemExit):
            self.run_json(M.cmd_tun_uninstall)
        self.assertEqual(self.stops(), [])
        self.assertTrue(M.SYS_UNIT.exists() and M.TUN_RECORD.exists())

    def test_user_paths_never_stop_a_foreign_unit(self):
        # off, cleanup and tun-remove (stop_service) and the tun2socks unit's
        # ExecStartPre/ExecStopPost (tun-unit) act only on our own root unit.
        self.active = True
        other = "/run/systemd/system/" + M.TUN_SERVICE
        foreign_loaded = [
            {"LoadState": "loaded", "ActiveState": "active", "FragmentPath": other},
            {"LoadState": "loaded", "ActiveState": "active", "FragmentPath": str(M.SYS_UNIT),
             "DropInPaths": "/etc/systemd/system/%s.d/x.conf" % M.TUN_SERVICE},
            {"LoadState": "loaded", "ActiveState": "active", "FragmentPath": str(M.SYS_UNIT),
             "NeedDaemonReload": "yes"},
        ]
        for props in foreign_loaded:
            with self.subTest(props=props):
                self.loaded = props
                M.stop_service()
                for verb in ("start", "stop"):
                    with self.assertRaises(SystemExit):
                        self.run_json(lambda: M.cmd_tun_unit(verb))
                self.assertEqual(self.root_unit_stops(), [])
        # loaded from our path, but the file there is not what we wrote
        self.loaded = None
        M.SYS_UNIT.parent.mkdir(parents=True)
        M.SYS_UNIT.write_text("[Service]\nExecStart=/usr/bin/true\n")
        M.wanted_mark().touch()
        M.stop_service()
        self.assertFalse(M.wanted_mark().exists())        # off is never read as a drop
        with self.assertRaises(SystemExit):
            self.run_json(lambda: M.cmd_tun_unit("stop"))
        self.assertEqual(self.root_unit_stops(), [])
        # ours, but another user's setup
        M.SYS_UNIT.unlink()
        self.run_json(M.cmd_tun_install)
        rec = json.loads(M.TUN_RECORD.read_text())
        rec["uid"] += 1
        M.TUN_RECORD.write_text(json.dumps(rec))
        M.stop_service()
        self.assertEqual(self.root_unit_stops(), [])

    def test_user_paths_stop_our_own_unit(self):
        self.run_json(M.cmd_tun_install)
        self.calls.clear()
        self.active = True
        M.stop_service()
        self.assertEqual(len(self.root_unit_stops()), 1)
        self.assertTrue(self.run_json(lambda: M.cmd_tun_unit("stop"))["ok"])
        self.assertEqual(len(self.root_unit_stops()), 2)
        M.SYS_UNIT.unlink()                                 # nothing of that name loaded
        self.assertFalse(self.run_json(lambda: M.cmd_tun_unit("stop"))["stopped"])

    def test_off_rewrites_an_old_tun2socks_unit_first(self):
        # a pre-check unit would stop the root unit straight from systemctl
        M.UNIT_DIR.mkdir(parents=True)
        M.T2S_UNIT.write_text("[Service]\nExecStopPost=%s stop --no-ask-password %s\n"
                              % (M.SYSTEMCTL, M.TUN_SERVICE))
        M.stop_service()
        self.assertEqual(M.T2S_UNIT.read_text(), M.t2s_unit_text())
        reload_at = self.calls.index((M.SYSTEMCTL, "--user", "daemon-reload"))
        stop_at = self.calls.index((M.SYSTEMCTL, "--user", "disable", "--now", M.T2S_SERVICE))
        self.assertLess(reload_at, stop_at)

    def test_setup_without_a_record_adopts_identical_files(self):
        # installs from before the record existed: identical content is ours
        self.run_json(M.cmd_tun_install)
        M.TUN_RECORD.unlink()
        self.run_json(M.cmd_tun_install)
        M.TUN_RECORD.unlink()
        res = self.run_json(M.cmd_tun_uninstall)
        self.assertEqual(len(res["removed"]), 2)


class Hardening(Base):
    def test_root_write_all_restores_previous_files(self):
        # As a user the chown to root fails, which drives the rollback path.
        if os.geteuid() == 0:
            self.skipTest("running as root")
        old = self.tmp / "unit.service"
        old.write_text("previous\n")
        new = self.tmp / "rule.rules"
        with self.assertRaises(SystemExit):
            M._root_write_all([(old, "replacement\n"), (new, "fresh\n")])
        self.assertEqual(old.read_text(), "previous\n")
        self.assertFalse(new.exists())

    def test_cleanup_removes_units_keeps_config(self):
        saved = M.uctl, M.sctl, M.apply_system_proxy, M.SYS_UNIT, M._escalate
        calls = []
        ok = type("R", (), {"returncode": 0, "stdout": "", "stderr": ""})()
        M.uctl = lambda *a, **k: calls.append(a) or ok
        M.sctl = lambda *a, **k: ok
        M.apply_system_proxy = lambda st, on: calls.append(("proxy", on))
        M.SYS_UNIT = self.tmp / "no-tun.service"              # TUN never set up
        M._escalate = lambda verb: self.fail("no privileged step without TUN")
        try:
            M.UNIT_DIR.mkdir(parents=True)
            for p in (M.UNIT, M.T2S_UNIT, M.UNIT_DIR / "omarchy-xray-tun-login.service"):
                p.write_text("[Unit]\n")
            M.CFG.mkdir(parents=True)
            M.STATE.write_text(json.dumps(self.state([self.node("trojan-ws")])))
            M.cmd_cleanup()
            self.assertEqual(list(M.UNIT_DIR.iterdir()), [])
            self.assertTrue(M.STATE.exists())                   # subscriptions stay
            self.assertIn(("proxy", False), calls)
            self.assertIn(("disable", M.SERVICE), calls)
        finally:
            M.uctl, M.sctl, M.apply_system_proxy, M.SYS_UNIT, M._escalate = saved

    def test_sub_error_never_carries_the_url(self):
        def boom(url, via_proxy=False):
            raise RuntimeError("download failed for %s" % url)
        saved = M.fetch
        M.fetch = boom
        try:
            st = self.state([self.node("trojan-ws")], subs=[{"url": "https://sub.example.com/secret-token?k=1"}])
            M.fetch_subs(st, None)
            err = st["subs"][0]["error"]
            self.assertNotIn("secret-token", err)
            self.assertIn("sub.example.com", err)
        finally:
            M.fetch = saved

    def test_import_refuses_url_in_argv(self):
        with self.assertRaises(SystemExit):
            M.secret_url_from_arg("https://sub.example.com/secret-token")


class LatencyTest(Base):
    def test_stop_keeps_finished_results(self):
        ns = [self.node(k) for k in LINKS][:3]
        M.CFG.mkdir(parents=True, exist_ok=True)
        M.STATE.write_text(json.dumps(self.state(ns)))
        calls = []

        def fake_probe(batch, iface, rundir):
            calls.append(batch)
            if len(calls) == 2:
                M._on_term(15, None)             # Stop pressed while batch 2 runs
            return ["%dms" % (100 + len(calls))] * len(batch)

        saved = M._probe_batch, M.TEST_BATCH, M.CURL, M.tun_active
        M._probe_batch, M.TEST_BATCH, M.CURL, M.tun_active = fake_probe, 1, "/bin/sh", lambda: False
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                M.cmd_test([])
        finally:
            M._probe_batch, M.TEST_BATCH, M.CURL, M.tun_active = saved
            M._STOP.clear()
        self.assertEqual(len(calls), 2)                              # batch 3 never started
        self.assertEqual(json.loads(M.LAT.read_text()), {ns[0]["id"]: "101ms"})
        self.assertTrue(json.loads(buf.getvalue())["stopped"])


class ManualServers(Base):
    """Share links and Xray JSON pasted into the import field."""

    def setUp(self):
        super().setUp()
        self._stubs = {k: getattr(M, k) for k in ("write_config", "running_units", "fetch")}
        M.write_config = lambda st: None
        M.running_units = lambda: (False, False)

        def no_network(*a, **kw):
            raise OSError("offline")
        M.fetch = no_network

    def tearDown(self):
        for k, v in self._stubs.items():
            setattr(M, k, v)
        super().tearDown()

    def imp(self, text):
        os.environ["OMARCHY_XRAY_SUB_URL"] = text
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            M.cmd_import("-")
        return json.loads(buf.getvalue())

    def test_links_collect_in_one_manual_group(self):
        M.save_state(self.state([self.node("trojan-ws")]))
        two = LINKS["vless-ws-tls"] + "\n" + LINKS["ss-sip002"]
        self.assertEqual(self.imp(two)["manual"], 2)
        self.imp(LINKS["hy2-obfs"])
        self.imp(two)                                    # the same paste twice: kept once
        st = M.load_state()
        self.assertEqual(st["subs"][1], {"local": [two, LINKS["hy2-obfs"]], "title": "Manual",
                                         "fetched": st["subs"][1]["fetched"], "error": ""})
        self.assertEqual(sorted(n["name"] for n in st["nodes"] if n["sub"] == 1),
                         ["HY2", "SS", "WS"])
        self.assertEqual([n["name"] for n in st["nodes"] if n["sub"] == 0], ["Trojan"])

    def test_xray_json_config_and_bare_outbound(self):
        ob = {"protocol": "vless", "tag": "proxy",
              "settings": {"vnext": [{"address": "j.example.com", "port": 443,
                                      "users": [{"id": UUID, "encryption": "none"}]}]},
              "streamSettings": {"network": "ws", "security": "tls",
                                 "wsSettings": {"path": "/j"}}}
        full = json.dumps({"remarks": "From JSON", "inbounds": [],
                           "outbounds": [ob, {"tag": "direct", "protocol": "freedom"}]}, indent=2)
        self.assertEqual(self.imp(full)["manual"], 1)    # multi-line, as pasted
        bare = dict(ob, streamSettings=dict(ob["streamSettings"], wsSettings={"path": "/k"}))
        self.imp(json.dumps(bare))
        names = sorted(n["name"] for n in M.load_state()["nodes"])
        self.assertEqual(names, ["From JSON", "j.example.com"])

    def test_nothing_usable_is_refused_and_not_stored(self):
        M.save_state(self.state([self.node("trojan-ws")]))
        for text in ("hello", "foo://bar", "{\"outbounds\": [{\"protocol\": \"freedom\"}]}",
                     "http://sub.example.com/x"):
            with self.subTest(text=text), self.assertRaises(SystemExit):
                self.imp(text)
        self.assertEqual(len(M.load_state()["subs"]), 1)

    def test_status_and_update_keep_the_text_private_and_offline(self):
        M.save_state(self.state([self.node("trojan-ws")]))
        self.imp(LINKS["vless-ws-tls"])
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            M.cmd_status()
        data = json.loads(buf.getvalue())
        self.assertNotIn(UUID, buf.getvalue())
        self.assertEqual((data["subs"][1]["local"], data["subs"][1]["url"]), (True, ""))
        self.assertFalse(data["subs"][0]["local"])
        st = M.load_state()
        nodes = M.fetch_subs(st)                          # the URL fails, Manual is parsed
        self.assertEqual(sorted(n["name"] for n in nodes), ["Trojan", "WS"])
        self.assertEqual(st["subs"][1]["error"], "")

    def test_new_subscription_that_fails_is_an_error_and_not_kept(self):
        M.save_state(self.state([self.node("trojan-ws")]))
        with self.assertRaises(SystemExit):
            self.imp("https://other.example.com/token")       # fetch is offline
        self.assertEqual(len(M.load_state()["subs"]), 1)

    def test_subremove_out_of_range_index_never_matches_a_host(self):
        M.save_state(self.state([self.node("trojan-ws")], subs=[{"url": "https://s1.example.com/x"}]))
        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
            M.cmd_subremove("1")
        self.assertEqual(len(M.load_state()["subs"]), 1)

    def test_dns_in_proxy_mode_does_not_restart(self):
        M.save_state(self.state([self.node("trojan-ws")]))
        saved = M.restart_if_running
        M.restart_if_running = lambda st: self.fail("proxy mode does not use the DNS preset")
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                M.cmd_dns("quad9")
        finally:
            M.restart_if_running = saved
        self.assertEqual(M.load_state()["dns"], "quad9")

    def test_subremove_manual_by_host_name(self):
        M.save_state(self.state([self.node("trojan-ws")]))
        self.imp(LINKS["vless-ws-tls"])
        with contextlib.redirect_stdout(io.StringIO()):
            M.cmd_subremove("manual")
        st = M.load_state()
        self.assertEqual(len(st["subs"]), 1)
        self.assertEqual([n["name"] for n in st["nodes"]], ["Trojan"])


class StatusShape(Base):
    def test_status_json(self):
        ns = [self.node("vless-ws-tls"), self.node("hy2-obfs")]
        M.save_state(self.state(ns, selected="auto"))
        M.running_units = lambda: (False, False)
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            M.cmd_status()
        data = json.loads(buf.getvalue())
        self.assertEqual(data["nodes"][0]["key"], "auto")
        self.assertEqual({n["key"] for n in data["nodes"][1:]}, {n["id"] for n in ns})
        self.assertEqual(data["nodes"][2]["net"], "hysteria2")
        self.assertNotIn("sub.example.com/x", json.dumps(data))
        self.assertEqual(data["subs"][0]["url"], "https://sub.example.com/***")
        self.assertTrue(data["sessionStart"])
        with contextlib.redirect_stdout(io.StringIO()) as again:
            M.cmd_status()
        self.assertFalse(json.loads(again.getvalue())["sessionStart"])   # once per session
        self.assertEqual(self.proxy_calls, [False])       # left-over proxy settings cleared once
        self.assertFalse(M.wanted_mark().exists())        # nothing turned on in this session
        self.assertIn("ExecStartPost=-%s proxy-sync\n" % M.SELF, M.user_unit_text())


if __name__ == "__main__":
    unittest.main()
