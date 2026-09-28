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
            "CFG", "CONF", "STATE", "LAT", "CUSTOM", "UNIT_DIR", "UNIT", "LOGIN_UNIT",
            "XRAY", "host_has_v6", "bootstrap_dns", "running_units")}
        M.CFG = self.tmp / "cfg"
        M.CONF = M.CFG / "config.json"
        M.STATE = M.CFG / "state.json"
        M.LAT = M.CFG / "latency.json"
        M.CUSTOM = M.CFG / "custom.json"
        M.UNIT_DIR = self.tmp / "units"
        M.UNIT = M.UNIT_DIR / M.SERVICE
        M.LOGIN_UNIT = M.UNIT_DIR / M.LOGIN_SERVICE
        M.XRAY = XRAY_BIN if HAVE_XRAY else str(self.tmp / "no-xray")
        M.host_has_v6 = lambda: True
        self._core_ver = list(M._CORE_VER)
        M._CORE_VER[:] = [None]          # link policy as for an unknown (= latest) core
        M.bootstrap_dns = lambda custom: ["192.168.1.1", "1.1.1.1"]
        self._env = os.environ.get("XRAY_LOCATION_ASSET")
        if HAVE_XRAY:
            os.environ["XRAY_LOCATION_ASSET"] = os.path.dirname(os.path.realpath(XRAY_BIN))
        os.environ["XDG_RUNTIME_DIR"] = str(self.tmp)

    def tearDown(self):
        M._CORE_VER[:] = self._core_ver
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
        saved = list(M._CORE_VER)
        try:
            M._CORE_VER[:] = [(26, 6, 27)]            # before the core refused it
            self.assertEqual(M.parse_link(link)["sec"], "none")
            M._CORE_VER[:] = [(26, 7, 11)]
            with self.assertRaises(M.Skip):
                M.parse_link(link)
        finally:
            M._CORE_VER[:] = saved

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
        conf = M.build_config(self.state(ns, mode="tun"))
        tun = conf["inbounds"][0]
        self.assertEqual(tun["protocol"], "tun")
        self.assertEqual(tun["settings"]["autoOutboundsInterface"], "auto")
        self.assertEqual(tun["settings"]["autoSystemRoutingTable"], ["0.0.0.0/0", "::/0"])
        self.assertEqual(conf["routing"]["rules"][0]["outboundTag"], "dns-out")
        proxy = conf["outbounds"][0]
        self.assertEqual(proxy["streamSettings"]["sockopt"]["domainStrategy"], "UseIPv4v6")
        boot = [s for s in conf["dns"]["servers"] if isinstance(s, dict)]
        self.assertTrue(all(s["tag"] == "dns-bootstrap" for s in boot))
        self.assertIn("full:" + ns[0]["host"], boot[0]["domains"])
        self.assertCoreAccepts(conf)

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
        t = M.tun_unit_text("alice", "alice", "/home/alice/.config/omarchy-xray/config.json",
                            "/usr/bin/xray", "/usr/share/xray", "/usr/bin/resolvectl",
                            "/usr/bin/udevadm")
        self.assertIn("User=alice\n", t)
        self.assertIn("ExecStart=/usr/bin/xray run -c /home/alice/.config/omarchy-xray/config.json\n", t)
        self.assertIn("AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE\n", t)
        self.assertIn("NoNewPrivileges=yes\n", t)
        # ProtectClock implies DeviceAllow=char-rtc (closed device policy)
        self.assertIn("DeviceAllow=/dev/net/tun rw\n", t)
        self.assertIn("ExecStartPost=-+/usr/bin/udevadm wait --timeout=15 /sys/class/net/xray0\n", t)
        self.assertIn("ExecStartPost=-+/usr/bin/resolvectl dns xray0 198.18.0.2\n", t)
        for line in t.splitlines():
            if line.startswith("ExecStart"):
                self.assertNotIn("omarchy-xray ", line.split("=", 1)[1].split()[0])

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

    def test_root_owned_check(self):
        p = self.tmp / "xray"
        p.write_text("#!/bin/sh\n")
        os.chmod(p, 0o755)
        if os.geteuid() == 0:
            os.chown(p, 1000, 1000)
        self.assertFalse(M._root_owned_ok(str(p)))

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
        M.SYS_UNIT.write_text("[Unit]\n")
        try:
            self.assertTrue(M.tun_installed())
        finally:
            os.chmod(rules, 0o755)
            M.SYS_UNIT, M.POLKIT_RULE = saved


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


if __name__ == "__main__":
    unittest.main()
