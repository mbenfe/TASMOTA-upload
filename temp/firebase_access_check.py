import json
import re
import urllib.request
import urllib.error
from pathlib import Path

secret = Path('.secrets').read_text(encoding='utf-8-sig').strip()
parts = secret.split(':', 1)
email_pattern = r'[^\s:]+@[^\s:]+\.[^\s:]+'
if len(parts) != 2:
    raise SystemExit('Credential format is not recognized; no sign-in attempted.')
if re.fullmatch(email_pattern, parts[0].strip()):
    email, password = parts[0].strip(), parts[1]
elif re.fullmatch(email_pattern, parts[1].strip()):
    password, email = parts[0], parts[1].strip()
else:
    raise SystemExit('No unambiguous email/password pair; no sign-in attempted.')
options = Path('D:/Programming/flutter/FLUTTER-mobile-adomob_new/lib/firebase/firebase_options.dart').read_text()
api_key = re.search(r"apiKey:\s*'([^']+)'", options).group(1)
project = re.search(r"projectId:\s*'([^']+)'", options).group(1)

def request(url, data=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(url, data=json.dumps(data).encode() if data is not None else None, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=25) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        body = json.loads(exc.read())
        error = body.get('error', {})
        # Print only standard error codes, never request contents or tokens.
        code = error.get('status') or error.get('message', '').split(' : ')[0]
        if not re.fullmatch(r'[A-Z_0-9]+', code):
            code = 'REQUEST_FAILED'
        raise SystemExit(f'HTTP {exc.code}: {code}')
    except urllib.error.URLError as exc:
        reason = exc.reason
        print('Network error type:', type(reason).__name__)
        print('Error code:', getattr(reason, 'errno', None))
        print('TLS verification:', getattr(reason, 'verify_message', None))
        raise SystemExit('NETWORK_CONNECTION_FAILED')

auth = request('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=' + api_key,
               {'email': email, 'password': password, 'returnSecureToken': True})
print('Firebase authentication successful.')
result = request(f'https://firestore.googleapis.com/v1/projects/{project}/databases/(default)/documents/configurations?pageSize=1', token=auth['idToken'])
print('Firestore configurations read successful; documents returned:', len(result.get('documents', [])))
print('No Firestore data changed. Credentials and tokens were not saved.')
