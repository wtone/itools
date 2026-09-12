#!/usr/bin/env python3
"""Create a persistent local development identity; never suitable for Developer ID distribution."""
from pathlib import Path
import os, subprocess, secrets, json, plistlib
root=Path.home()/'Library/Application Support/iTools Development/Signing'
def run(args, **kwargs):
 result = subprocess.run(args, capture_output=True, **kwargs)
 if result.returncode: raise RuntimeError(Path(args[0]).name + ': ' + result.stderr.decode(errors='replace'))
 return result
root.mkdir(parents=True,exist_ok=True); root.chmod(0o700)
keychain=root/'itools-signing.keychain-db'; passwordFile=root/'keychain-password'
cert=root/'itools-local-signing.cer'; info=root/'identity.json'
if info.exists():
 print('Existing stable local identity:',info); raise SystemExit(0)
assert not keychain.exists(), 'Incomplete signing setup; inspect before retrying'
password=secrets.token_urlsafe(32); passwordFile.write_text(password); passwordFile.chmod(0o600)
config=root/'certificate.cnf'
config.write_text('[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=iTools Local Development\nO=iTools Local\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nsubjectKeyIdentifier=hash\n')
key=root/'temporary-key.pem'; pem=root/'temporary-certificate.pem'; p12=root/'temporary-identity.p12'
# Restrict every generated key/identity file before invoking the tools.
os.umask(0o077)
run(['/usr/bin/openssl','req','-x509','-newkey','rsa:3072','-nodes','-keyout',str(key),'-out',str(pem),'-days','3650','-config',str(config)])
run(['/usr/bin/openssl','x509','-in',str(pem),'-outform','DER','-out',str(cert)])
run(['/usr/bin/openssl','pkcs12','-export','-inkey',str(key),'-in',str(pem),'-out',str(p12),'-passout','stdin'],input=(password+'\n').encode())
original=run(['/usr/bin/security','list-keychains','-d','user']).stdout.decode()
# Preserve the user's search list; codesign receives this keychain explicitly.
import shlex
search=shlex.split(original)
try:
 run(['/usr/bin/security','create-keychain','-p',password,str(keychain)])
 run(['/usr/bin/security','set-keychain-settings','-lut','21600',str(keychain)])
 run(['/usr/bin/security','unlock-keychain','-p',password,str(keychain)])
 run(['/usr/bin/security','import',str(p12),'-k',str(keychain),'-P',password,'-T','/usr/bin/codesign'])
 run(['/usr/bin/security','set-key-partition-list','-S','apple-tool:,apple:','-s','-k',password,str(keychain)])
finally:
 run(['/usr/bin/security','list-keychains','-d','user','-s',*search])
 for f in [key,pem,p12]: f.unlink(missing_ok=True)
import hashlib
identity=hashlib.sha1(cert.read_bytes()).hexdigest().upper()
info.write_text(json.dumps({'identity':identity,'keychain':str(keychain)},indent=2)+'\n'); info.chmod(0o600)
print('Created isolated local signing identity:',identity)
print('Keychain:',keychain)
run(['/usr/bin/security','add-trusted-cert','-r','trustRoot','-p','codeSign','-k',str(keychain),str(cert)])
print('Trust limited to this user and the code signing policy. No system root trust or privacy access is granted.')
