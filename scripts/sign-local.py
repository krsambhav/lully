#!/usr/bin/env python3
"""Sign local builds with one private certificate; never change system trust."""
from pathlib import Path
import hashlib, json, os, secrets, subprocess, sys, tempfile

bundle = Path(sys.argv[1]).resolve()
identity = os.environ.get('LULLY_SIGNING_IDENTITY')
if identity:
    subprocess.run(['codesign','--force','--sign',identity,str(bundle)],check=True)
    raise SystemExit(0)
root = Path.home() / 'Library/Application Support/Lully/Signing'
root.mkdir(parents=True,exist_ok=True,mode=0o700)
root.chmod(0o700)
keychain = root / 'local-signing.keychain-db'
config = root / 'identity.json'
def run(args, **kwargs):
    result = subprocess.run(args,capture_output=True,text=True,**kwargs)
    if result.returncode:
        # Never log command arguments: some contain private keychain passwords.
        raise RuntimeError(result.stderr.strip() or 'Signing command failed')
    return result.stdout
if not config.exists():
    password=secrets.token_urlsafe(32)
    original=run(['security','list-keychains','-d','user'])
    import shlex
    original_paths=shlex.split(original)
    try:
        run(['security','create-keychain','-p',password,str(keychain)])
        with tempfile.TemporaryDirectory(dir=root) as scratch:
            work=Path(scratch)
            cert=work/'certificate.pem'; private=work/'key.pem'; p12=work/'identity.p12'
            env=dict(os.environ,LULLY_P12_PASSWORD=password)
            run(['openssl','req','-x509','-newkey','rsa:3072','-nodes','-keyout',str(private),'-out',str(cert),'-days','3650','-subj','/CN=Lully Local Development/','-addext','keyUsage=critical,digitalSignature','-addext','extendedKeyUsage=critical,codeSigning','-addext','basicConstraints=critical,CA:FALSE'])
            run(['openssl','pkcs12','-export','-inkey',str(private),'-in',str(cert),'-out',str(p12),'-keypbe','PBE-SHA1-3DES','-certpbe','PBE-SHA1-3DES','-macalg','sha1','-passout','env:LULLY_P12_PASSWORD'],env=env)
            run(['security','import',str(p12),'-k',str(keychain),'-P',password,'-T','/usr/bin/codesign'])
            run(['security','set-key-partition-list','-S','apple-tool:,apple:','-s','-k',password,str(keychain)])
            cert_der=subprocess.check_output(['openssl','x509','-in',str(cert),'-outform','DER'])
            certificate_hash=hashlib.sha1(cert_der).hexdigest().upper()
            with os.fdopen(os.open(config,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as f:
                json.dump({'password':password,'identity':certificate_hash},f)
    finally:
        # This identity is scoped to this build script, not the user's default search list.
        run(['security','list-keychains','-d','user','-s',*original_paths])
values=json.loads(config.read_text())
run(['security','unlock-keychain','-p',values['password'],str(keychain)])
run(['codesign','--force','--sign',values['identity'],'--keychain',str(keychain),'--timestamp=none',str(bundle)])
run(['codesign','--verify','--deep','--strict',str(bundle)])
print('Signed with the persistent Lully local-development identity.')
