import asyncio
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from extract import extract

work = tempfile.TemporaryDirectory()
files = extract(work.name)
sys.path.insert(0, work.name)
from gateway import Gateway
from nodes import Nodes, permitted, merge_subscriptions
from dns_clients import DNSClients
from features import apply_policy, policies, policy_key

class RegressionTests(unittest.TestCase):
    def gateway(self):
        return Gateway({'assets': work.name, 'nodes_state': work.name})

    def test_remote_mount_keeps_axios_paths_relative(self):
        for root in ('/', '/edge/'):
            source = f'''<head><script>const basePath = '{root}';
axios.defaults.baseURL=basePath;
HttpUtil.post('/panel/api/inbounds/add', {{settings:'{{}}'}});
HttpUtil.get('/panel/api/clients/assignable');
const core={{basePath:'{root}'}};
const tab={{key:'{root}panel/inbounds'}};
window.ALIREZA={{"base":"{root}","dns":false}};</script>
<script src="{root}assets/js/util/index.js"></script></head>'''
            mount = '/master/_alireza/remote/abc/'
            body = self.gateway().nodes.mount_html(source, {'endpoint':'https://edge.example'}, mount, '/master/', 'abc')
            self.assertIn("HttpUtil.post('/panel/api/inbounds/add'", body)
            self.assertIn("HttpUtil.get('/panel/api/clients/assignable'", body)
            self.assertIn('const basePath = '+json.dumps(mount), body)
            self.assertIn('basePath:'+json.dumps(mount), body)
            self.assertIn('key:'+json.dumps(mount+'panel/inbounds'), body)
            self.assertIn('src="'+mount+'assets/', body)

    def test_adguard_html_exactly_unchanged(self):
        page = '<html><head><title>AdGuard Home</title></head><body>AdGuard Home<script>let filter=1;</script></body></html>'
        self.assertEqual(self.gateway().brand_html(page, '/secret/', agh=True), page)

    def test_dns_shell_has_only_native_interface(self):
        upstream = '''<head><link href="/assets/main.css"></head><script>const basePath = '/';</script><script>Vue.component('a-sidebar', {});</script>'''
        shell = self.gateway().dns_shell(upstream, '/', managed=True)
        self.assertNotIn('dns-clients.js', shell)
        self.assertNotIn('id="alireza-dns-clients"', shell)
        self.assertIn('src="/dns/"', shell)
        self.assertNotIn(' hidden style=', shell)

    def test_retired_dns_does_not_create_state(self):
        with tempfile.TemporaryDirectory() as folder:
            client = DNSClients(SimpleNamespace(config={},nodes=SimpleNamespace(folder=Path(folder))))
            asyncio.run(client.start())
            self.assertIsNone(client.db)
            self.assertFalse((Path(folder)/'dns-clients.sqlite3').exists())
            asyncio.run(client.stop())

    def test_policy_preserves_other_users_and_custom_routes(self):
        original={'outbounds':[{'tag':'direct','protocol':'freedom'}],
                  'routing':{'rules':[{'type':'field','user':['other'],'outboundTag':'direct'}]}}
        saved=copy.deepcopy(original)
        result=apply_policy(original,'one',{'ads':True,'gaming':True,'domains':['example.com']})
        self.assertEqual(original,saved)
        self.assertIn(original['routing']['rules'][0],result['routing']['rules'])
        self.assertTrue(policies(result,'one')['ads'])
        self.assertFalse(policies(result,'other')['ads'])
        self.assertEqual(policies(result,'one')['domains'],['example.com'])
        game=next(r for r in result['routing']['rules'] if r.get('ruleTag')==policy_key('one')+'-gaming')
        self.assertEqual(game['port'],'1-52,54-65535')
        cleared=apply_policy(result,'one',{'ads':False,'gaming':False,'domains':[]})
        self.assertEqual(cleared['routing']['rules'],original['routing']['rules'])

    def test_upgrade_never_rewrites_adguard_yaml(self):
        source=(Path(__file__).resolve().parents[1]/'install.sh').read_text()
        self.assertNotIn("<<'MANAGED_DOH'",source)
        self.assertIn('"$backup/units"',source)
        self.assertIn('"$backup/cli"',source)
        self.assertNotIn('systemctl stop alirezapanel alirezapanel-vpn alirezapanel-dns || true',source)

    def test_existing_init_preserves_config_certificates_and_dns(self):
        import manage
        import types
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);etc=root/'etc';etc.mkdir();adguard=root/'adguard';adguard.mkdir()
            saved={etc/'gateway.json':'{"preserved":true}',etc/'cert.pem':'existing-certificate',
                   adguard/'AdGuardHome.yaml':'dns: {port: 5353}\n'}
            for path,content in saved.items():path.write_text(content)
            # Existing-config branch returns before bcrypt/socket/certificate generation.
            with patch.object(manage,'ROOT',root),patch.object(manage,'ETC',etc),patch.dict(sys.modules,{'bcrypt':types.ModuleType('bcrypt')}):
                manage.init()
            for path,content in saved.items():self.assertEqual(path.read_text(),content)

    def test_legacy_dns_state_is_retained(self):
        import sqlite3
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'dns-clients.sqlite3'
            with sqlite3.connect(path) as db:
                db.execute('CREATE TABLE clients(id TEXT PRIMARY KEY,config TEXT)')
                db.execute('INSERT INTO clients VALUES(?,?)',('legacy-id','{"name":"existing"}'))
            client=DNSClients(SimpleNamespace(config={},nodes=SimpleNamespace(folder=Path(folder))))
            async def run():
                await client.start()
                self.assertEqual(tuple(client.db.execute('SELECT * FROM clients').fetchone()),('legacy-id','{"name":"existing"}'))
                await client.stop()
            asyncio.run(run())
            self.assertTrue(path.exists())

    def test_agent_cannot_escape_to_admin_settings(self):
        for path in ('panel/admins/list','panel/settings','login','../panel/api/inbounds/list','/panel/api/inbounds/list','panel/api/inbounds/../admins/list'):
            self.assertFalse(permitted('GET', path), path)
        self.assertTrue(permitted('POST','panel/api/inbounds/add'))
        self.assertTrue(permitted('GET','panel/api/clients/assignable'))
        self.assertFalse(permitted('DELETE','panel/api/inbounds/add'))

    def test_plain_access_denial_has_logout(self):
        # The full native 403 branch is exercised by native_integration.py.
        source = files['gateway.py']
        self.assertIn("response.status == 403", source)
        self.assertIn("html.escape(base+'logout'", source)
        self.assertNotIn('bar.append(policy,tls,dns)', files['features.js'])

    def test_content_routes_and_target_capture(self):
        self.assertIn("'panel/content'",files['gateway.py'])
        self.assertIn('const destination=base;',files['features.js'])
        self.assertIn("apiAt(destination,'policy'",files['features.js'])

    def test_subscription_preserves_native_links(self):
        raw,_=merge_subscriptions('links',[b'vless://first@example:443',b'vless://first@example:443\ntrojan://second@example:8443'],['A','B'])
        import base64
        self.assertEqual(base64.b64decode(raw).decode().splitlines(),['vless://first@example:443','trojan://second@example:8443'])

    def test_polling_deduplicated_and_hidden_pause(self):
        g=self.gateway()
        source='''<head></head><script>        const pollInterval = setInterval(async () => {
          if (window.wsClient && window.wsClient.isConnected) {
            clearInterval(pollInterval);
            return;
          }
          try {
            await this.getStatus();
            await this.getCoreStatuses();
          } catch (e) {
            console.error(e);
          }
        }, 2000);</script>'''
        result=g.brand_html(source,'/')
        self.assertIn('if (this._apPollTimer) return;',result)
        self.assertIn('document.hidden || polling',result)
        self.assertIn('finally { polling = false; }',result)
        self.assertIn('}, 5000)',result)

if __name__=='__main__': unittest.main()
