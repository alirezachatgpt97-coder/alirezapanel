"""Optional real pinned-backend test. Runs only isolated loopback scratch panels.
Usage: python3 tests/native_integration.py /path/to/vpn-ui-amd64 [output-dir]
Never runs install.sh, systemd, a public server or a GitHub write.
"""
import asyncio
import hashlib
import json
import re
import os
import socket
import sqlite3
import ssl
import subprocess
import sys
import tempfile
import time
from pathlib import Path
import aiohttp
from extract import extract
from yarl import URL

SHA='18ec321d9074b319bd5756508bbc523ab5d95450b832c406acdd72e987a2da8f'
BINARY=Path(sys.argv[1]).resolve()
with BINARY.open('rb') as stream:
    assert hashlib.file_digest(stream,'sha256').hexdigest()==SHA, 'Wrong backend binary'
OUTPUT=Path(sys.argv[2] if len(sys.argv)>2 else 'test-output').resolve()
OUTPUT.mkdir(parents=True,exist_ok=True)
PASSWORD='Scratch-Only-Password-9876'

def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1',0));return s.getsockname()[1]

async def main():
    with tempfile.TemporaryDirectory(prefix='native-test-',dir=OUTPUT) as folder:
        root=Path(folder);runtime=root/'runtime';extract(runtime);sys.path.insert(0,str(runtime))
        from gateway import create_app
        from aiohttp import web
        processes=[];runners=[];sessions=[];urls=[];configs=[]
        log=(OUTPUT/'native.log').open('w')
        try:
            for number,base in enumerate(('/master/',os.environ.get('NODE_BASE_PATH','/'))):
                dbdir=root/str(number);dbdir.mkdir();native=port();public=port()
                env=dict(os.environ,VPNUI_DB_FOLDER=str(dbdir),VPNUI_BIN_FOLDER=str(dbdir/'bin'),VPNUI_LOG_FOLDER=str(dbdir/'logs'),VPNUI_LOG_LEVEL='error')
                subprocess.run([str(BINARY),'setting','-port',str(native),'-listenIP','127.0.0.1','-webBasePath',base,'-username','testadmin','-password',PASSWORD],env=env,stdout=log,stderr=log,check=True)
                proc=subprocess.Popen([str(BINARY),'run'],env=env,cwd=dbdir,stdout=log,stderr=log);processes.append(proc)
                cert=dbdir/'cert.pem';key=dbdir/'key.pem'
                subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','2','-subj','/CN=localhost','-keyout',str(key),'-out',str(cert)],check=True,stdout=log,stderr=log)
                config={'assets':str(runtime),'vpn_db':str(dbdir/'vpn-ui.db'),'nodes_state':str(dbdir/'state'),'agh_origin':'http://127.0.0.1:1','tls_enabled':True,'tls_mode':'ip','tls_cert':str(cert),'tls_key':str(key),'host':'127.0.0.1'}
                configs.append(config)
                context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(cert,key)
                runner=web.AppRunner(create_app(config));await runner.setup();runners.append(runner)
                await web.TCPSite(runner,'127.0.0.1',public,ssl_context=context).start()
                session=aiohttp.ClientSession(connector=aiohttp.TCPConnector(ssl=False),cookie_jar=aiohttp.CookieJar(unsafe=True));sessions.append(session)
                urls.append('https://127.0.0.1:'+str(public)+base)
                for attempt in range(60):
                    try:
                        async with session.get(urls[-1]) as r:
                            if r.status==200:break
                    except aiohttp.ClientError:pass
                    await asyncio.sleep(.2)
                else:raise AssertionError('Native backend did not start')

            async def request(index,path,method='GET',data=None,json_body=None,session=None,html=False):
                client=session or sessions[index];headers={'X-Alirezapanel-Request':'1','Accept':'text/html' if html else 'application/json'}
                async with client.request(method,urls[index]+path,headers=headers,data=data,json=json_body,allow_redirects=False) as r:
                    raw=await r.read();return r.status,dict(r.headers),raw
            async def obj(index,path,method='GET',data=None,json_body=None,session=None):
                status,headers,raw=await request(index,path,method,data,json_body,session)
                assert status==200,(path,status,raw[:300])
                result=json.loads(raw)
                assert result.get('success',True) is True,(path,result)
                return result

            for i in range(2):await obj(i,'login','POST',{'username':'testadmin','password':PASSWORD})
            identity=await obj(1,'_alireza/nodes/identity','POST',json_body={})
            enrolled=await obj(0,'_alireza/nodes/add','POST',json_body={'certificate':identity['certificate'],'token':identity['token']})
            ident=enrolled['id'];mount='_alireza/remote/'+ident+'/'
            await obj(0,'_alireza/nodes/check','POST',json_body={'id':ident})
            status,_,raw=await request(0,mount+'panel/inbounds',html=True)
            assert status==200 and b'const basePath = '+json.dumps('/master/'+mount).encode() in raw
            assert b"HttpUtil.post('/panel/api/inbounds/" in raw, 'Axios URLs rewritten again'
            (OUTPUT/'remote-inbounds.html').write_bytes(raw)
            english_title=re.search(rb"pageTitle: '([^']*)'",raw).group(1)
            sessions[0].cookie_jar.update_cookies({'lang':'fa-IR'},response_url=URL(urls[0]))
            status,_,persian=await request(0,mount+'panel/inbounds',html=True)
            assert status==200 and re.search(rb"pageTitle: '([^']*)'",persian).group(1)!=english_title, 'Remote language selection ignored'
            sessions[0].cookie_jar.update_cookies({'lang':'en-US'},response_url=URL(urls[0]))
            defaults=await obj(0,mount+'panel/setting/defaultSettings','POST')
            assert isinstance(defaults['obj'],dict)
            inbound={'enable':'true','remark':'scratch-node-test','listen':'127.0.0.1','port':str(port()),'protocol':'vless','settings':json.dumps({'clients':[{'id':'739286e8-f81d-4e52-b3a4-843f233b5a18','email':'node-client','enable':True,'subId':'scratchsub'}],'decryption':'none'}),'streamSettings':json.dumps({'network':'tcp','security':'none','tcpSettings':{'header':{'type':'none'}}}),'sniffing':json.dumps({'enabled':True,'destOverride':['http','tls']}),'allocate':'{}','expiryTime':'0','total':'0','up':'0','down':'0'}
            await obj(0,mount+'panel/api/inbounds/add','POST',data=inbound)
            rows=(await obj(0,mount+'panel/api/inbounds/list'))['obj'];assert len(rows)==1
            iid=rows[0]['id'];inbound['remark']='updated-on-node'
            await obj(0,mount+'panel/api/inbounds/update/'+str(iid),'POST',data=inbound)
            assert not (await obj(0,'panel/api/inbounds/list'))['obj'], 'Remote mutation leaked to master'
            assert (await obj(0,mount+'panel/api/clients/assignable'))['obj']
            # Native client-membership mutation uses the same agent body stream.
            await obj(0,mount+'panel/api/inbounds/addClient','POST',data={'id':str(iid),'settings':json.dumps({'clients':[{'id':'2bddcf95-e77b-43bf-b513-079ca7d21aa2','email':'node-second','enable':True,'subId':'scratchsub2'}]})})
            listing=(await obj(0,mount+'panel/api/clients/list?search=node-second&size=1&page=1'))['obj']
            assert listing['size']==1 and listing['page']==1 and listing['total']==1
            multipart=aiohttp.FormData();multipart.add_field('remark','multipart-on-node',content_type='text/plain')
            await obj(0,mount+'panel/api/inbounds/update/'+str(iid),'POST',data=multipart)
            assert (await obj(0,mount+'panel/api/inbounds/list'))['obj'][0]['remark']=='multipart-on-node'
            denied,_,_=await request(0,mount+'panel/admins/list');assert denied==403
            # Native admin creation: no implicit permission escalation.
            for name,perms in [('limited',['accessInbounds']),('nopage',[''])]:
                await obj(0,'panel/admins/add','POST',data=[('username',name),('password',PASSWORD),('enable','true')]+[('permissions',p) for p in perms])
            limited=aiohttp.ClientSession(connector=aiohttp.TCPConnector(ssl=False),cookie_jar=aiohttp.CookieJar(unsafe=True));sessions.append(limited)
            await obj(0,'login','POST',data={'username':'limited','password':PASSWORD},session=limited)
            status,headers,raw=await request(0,'panel/',session=limited,html=True)
            assert status==307 and headers['Location']=='/master/panel/inbounds'
            assert (await request(0,'panel/inbounds',session=limited,html=True))[0]==200
            assert not (await obj(0,'panel/api/inbounds/list',session=limited))['obj']
            status,_,_=await request(0,'_alireza/nodes/list',session=limited);assert status==403
            # Grant exactly one of two master inbounds through native Admins API.
            inbound['port']=str(port());inbound['remark']='limited-grant'
            await obj(0,'panel/api/inbounds/add','POST',data=inbound)
            local_id=(await obj(0,'panel/api/inbounds/list'))['obj'][0]['id']
            private=dict(inbound,port=str(port()),remark='private-other-admin',settings=json.dumps({'clients':[],'decryption':'none'}))
            await obj(0,'panel/api/inbounds/add','POST',data=private)
            admin_id=next(a['id'] for a in (await obj(0,'panel/admins/list'))['obj'] if a['username']=='limited')
            await obj(0,'panel/admins/update/'+str(admin_id),'POST',data={'username':'limited','password':'','enable':'true','isSuperAdmin':'false','permissions':'accessInbounds','inboundIds':str(local_id)})
            granted=(await obj(0,'panel/api/inbounds/list',session=limited))['obj']
            assert [r['id'] for r in granted]==[local_id], 'Cross-admin inbound visibility'
            # Revocation is checked on the next request, not just at login.
            await obj(0,'panel/admins/update/'+str(admin_id),'POST',data={'username':'limited','password':'','enable':'false','isSuperAdmin':'false','permissions':'accessInbounds','inboundIds':str(local_id)})
            assert (await request(0,'panel/inbounds',session=limited,html=True))[0]==307
            await obj(0,'panel/admins/update/'+str(admin_id),'POST',data={'username':'limited','password':'','enable':'true','isSuperAdmin':'false','permissions':'accessInbounds','inboundIds':str(local_id)})
            wrong,_,raw=await request(0,'login','POST',data={'username':'limited','password':'wrong'},session=limited)
            assert json.loads(raw)['success'] is False
            await request(0,'logout',session=limited)
            assert (await request(0,'panel/inbounds',session=limited,html=True))[0]==307
            nopage=aiohttp.ClientSession(connector=aiohttp.TCPConnector(ssl=False),cookie_jar=aiohttp.CookieJar(unsafe=True));sessions.append(nopage)
            await obj(0,'login','POST',data={'username':'nopage','password':PASSWORD},session=nopage)
            status,_,raw=await request(0,'panel/',session=nopage,html=True)
            assert status==403 and b'/master/logout' in raw and b'Page access unavailable' in raw
            (OUTPUT/'no-access.html').write_bytes(raw)
            assert (await request(0,'panel/content',html=True))[0]==200
            assert (await request(0,'panel/nodes',html=True))[0]==200
            if os.environ.get('RUN_BROWSER')=='1':
                script=Path(__file__).with_name('browser_checks.js')
                process=await asyncio.create_subprocess_exec('node',str(script),urls[0],str(OUTPUT),ident,env=dict(os.environ,TMPDIR=str(root)))
                assert await process.wait()==0,'Browser tests failed'
            await obj(0,mount+'panel/api/inbounds/del/'+str(iid),'POST')
            await obj(1,'_alireza/nodes/rotate','POST',json_body={})
            assert (await request(0,mount+'panel/api/inbounds/list'))[0]==502,'Revoked token accepted'
            report={'backend_sha256':SHA,'node_base':os.environ.get('NODE_BASE_PATH','/'),'node':'TLS enrollment, status/catalog, mounted page, defaults, create/edit/delete inbound, add client, assignable, multipart/query fidelity, language forwarding, destination isolation, allowlist and token revocation passed','admin':'native create, password rejection, permitted landing, denied integration, explicit inbound-grant isolation, account revocation, empty grants notice/logout passed','system_install':'not executed; no systemd/kernel/full AdGuard test','browser':os.environ.get('RUN_BROWSER')=='1'}
            (OUTPUT/'results.json').write_text(json.dumps(report,indent=2))
            print(json.dumps(report,indent=2))
        finally:
            for client in sessions:await client.close()
            for runner in reversed(runners):await runner.cleanup()
            for proc in processes:
                proc.terminate()
            for proc in processes:
                try:proc.wait(timeout=5)
                except subprocess.TimeoutExpired:proc.kill();proc.wait()
            log.close()

asyncio.run(main())
