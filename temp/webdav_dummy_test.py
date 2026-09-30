import base64
import sys
import urllib.error
import urllib.request
import uuid

BASE = 'https://malek4b.synology.me:5006/webdav/tasmotafs/'
AUTH = 'Basic ' + base64.b64encode(sys.stdin.readline().strip().encode()).decode()

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

opener = urllib.request.build_opener(NoRedirect)

def request(method, url, data=None, headers=None):
    h = {'Authorization': AUTH}
    h.update(headers or {})
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    with opener.open(req, timeout=20) as response:
        body = response.read()
        print(method, response.status, url.removeprefix(BASE))
        return response.status, body

created = False
directory = BASE + 'pwx-dummy-' + uuid.uuid4().hex + '/'
temporary = directory + 'dummy.txt.pwx-upload-part'
target = directory + 'dummy.txt'
try:
    request('PROPFIND', BASE, headers={'Depth': '0'})
    status, _ = request('MKCOL', directory, data=b'')
    assert status == 201
    created = True
    payload = b'PWX WebDAV dummy test\nNo device data or credentials.\n'
    request('PUT', temporary, payload, {'Content-Type': 'application/octet-stream'})
    _, actual = request('GET', temporary)
    assert actual == payload, 'Uploaded bytes differ'
    request('MOVE', temporary, data=b'', headers={'Destination': target, 'Overwrite': 'T'})
    _, actual = request('GET', target)
    assert actual == payload, 'Renamed bytes differ'
    print('PASS: upload, read-back, MOVE and byte comparison')
except urllib.error.HTTPError as exc:
    print('FAILED: HTTP', exc.code, exc.reason)
except Exception as exc:
    print('FAILED:', type(exc).__name__, str(exc))
finally:
    if created:
        try:
            request('DELETE', directory)
            print('Cleanup complete: removed only this uniquely named test directory.')
        except Exception as exc:
            print('Cleanup failed:', type(exc).__name__, 'Test directory:', directory)
