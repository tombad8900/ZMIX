import http.server, os, re, sys, json
LOG='/tmp/mpvx/req.log'
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def _do(self, head):
        with open(LOG,'a') as f:
            f.write(json.dumps({'m':self.command,'p':self.path,'ua':self.headers.get('User-Agent'),'x':self.headers.get('X-Probe'),'range':self.headers.get('Range')})+'\n')
        fn='/tmp/mpvx/'+self.path.split('?')[0].lstrip('/')
        if not os.path.exists(fn): self.send_error(404); return
        data=open(fn,'rb').read(); n=len(data); s,e=0,n-1; code=200
        r=self.headers.get('Range')
        if r:
            m=re.match(r'bytes=(\d*)-(\d*)',r)
            if m.group(1)!='': s=int(m.group(1))
            if m.group(2)!='': e=min(int(m.group(2)),n-1)
            code=206
        self.send_response(code)
        self.send_header('Accept-Ranges','bytes'); self.send_header('Content-Length',str(e-s+1))
        if code==206: self.send_header('Content-Range',f'bytes {s}-{e}/{n}')
        self.send_header('Content-Type','video/mp4' if fn.endswith('mp4') else 'audio/mp4'); self.end_headers()
        if not head: self.wfile.write(data[s:e+1])
    def do_GET(self): self._do(False)
    def do_HEAD(self): self._do(True)
http.server.ThreadingHTTPServer(('127.0.0.1',8765),H).serve_forever()
