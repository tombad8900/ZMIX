import socket, json, subprocess, time, os, sys
mpv=['/tmp/mpvx/mpv.AppImage','--vo=null','--ao=null','--idle=yes','--no-terminal','--input-ipc-server=/tmp/mpvx/sock','--pause']
def run(label, headers):
    open('/tmp/mpvx/req.log','w').close()
    if os.path.exists('/tmp/mpvx/sock'): os.remove('/tmp/mpvx/sock')
    env=dict(os.environ,APPIMAGE_EXTRACT_AND_RUN='1')
    p=subprocess.Popen(mpv,env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    for _ in range(50):
        if os.path.exists('/tmp/mpvx/sock'): break
        time.sleep(.2)
    s=socket.socket(socket.AF_UNIX); s.connect('/tmp/mpvx/sock'); s.settimeout(3)
    def cmd(*c):
        s.sendall((json.dumps({'command':list(c)})+'\n').encode()); time.sleep(.6)
        try: return s.recv(65536).decode()[:200].replace('\n',' | ')
        except Exception as e: return str(e)
    if headers: print(label,'set hdr',cmd('set_property','http-header-fields',headers))
    print(label,'loadfile',cmd('loadfile','http://127.0.0.1:8765/v.mp4'))
    time.sleep(2)
    print(label,'audio-add',cmd('audio-add','http://127.0.0.1:8765/a.m4a','select','ext','auto'))
    time.sleep(2)
    print(label,'tracks',cmd('get_property','track-list/count'))
    cmd('quit'); p.wait(timeout=10)
    for l in open('/tmp/mpvx/req.log'): 
        d=json.loads(l); print(label,'REQ',d['p'],'ua=',d['ua'],'x=',d['x'])

def runC():
    label='C-reset'
    open('/tmp/mpvx/req.log','w').close()
    if os.path.exists('/tmp/mpvx/sock'): os.remove('/tmp/mpvx/sock')
    p=subprocess.Popen(mpv,env=dict(os.environ,APPIMAGE_EXTRACT_AND_RUN='1'),stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    for _ in range(50):
        if os.path.exists('/tmp/mpvx/sock'): break
        time.sleep(.2)
    s=socket.socket(socket.AF_UNIX); s.connect('/tmp/mpvx/sock'); s.settimeout(3)
    def cmd(*c):
        s.sendall((json.dumps({'command':list(c)})+'\n').encode()); time.sleep(.8)
        try: s.recv(65536)
        except Exception: pass
    cmd('set_property','http-header-fields',['User-Agent: UA-PROBE'])
    cmd('loadfile','http://127.0.0.1:8765/v.mp4'); time.sleep(2)
    cmd('set_property','http-header-fields',[])   # what media_kit on_unload does
    open('/tmp/mpvx/req.log','a').write('--- after reset, new muxed-like open ---\n')
    cmd('loadfile','http://127.0.0.1:8765/a.m4a'); time.sleep(2)
    cmd('quit'); p.wait(timeout=10)
    for l in open('/tmp/mpvx/req.log'):
        if l.startswith('---'): print(l.strip()); continue
        d=json.loads(l); print(label,'REQ',d['p'],'ua=',d['ua'])
runC()
