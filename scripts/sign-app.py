#!/usr/bin/env python3
"""Persistent local development signing; setup requires explicit user approval.

Usage: sign-app.py APP --setup     # Creates a private local identity once.
       sign-app.py APP             # Uses an existing identity; never creates one.

No trust-store changes. Only /usr/bin/codesign is authorized to use the key.
Never commit the private .local-signing directory.
"""
import os
import pathlib
import secrets
import shlex
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
STATE = ROOT / '.local-signing'

def run(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        # Never expose command arguments: security commands contain the password.
        detail = result.stderr.strip() if args[0] == 'codesign' else 'Command arguments and output withheld.'
        raise RuntimeError(f'{args[0]} failed (exit {result.returncode}). {detail}')
    return result.stdout.strip()

def main():
    if len(sys.argv) < 2:
        raise RuntimeError('Usage: sign-app.py APP [--setup]')
    app = pathlib.Path(sys.argv[1]).resolve()
    setup = '--setup' in sys.argv[2:]
    password_file = STATE / 'keychain-password'
    keychain = STATE / 'LocalWriter.keychain-db'
    cert = STATE / 'certificate.pem'
    if not setup and not all(p.exists() for p in [password_file, keychain, cert, STATE / 'imported']):
        raise RuntimeError('No complete signing identity. Explicitly approved --setup is required.')
    os.umask(0o077)
    STATE.mkdir(exist_ok=True)
    if not password_file.exists():
        password_file.write_text(secrets.token_hex(32))
    password = password_file.read_text().strip()
    if not cert.exists():
        config = STATE / 'openssl.cnf'
        config.write_text('''[req]
distinguished_name=dn
x509_extensions=extensions
prompt=no
[dn]
CN=LocalWriter Development
[extensions]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
''')
        run(['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-x509', '-sha256', '-days', '3650',
             '-config', str(config), '-keyout', str(STATE / 'private-key.pem'), '-out', str(cert)])
    if not keychain.exists():
        previous = shlex.split(run(['security', 'list-keychains', '-d', 'user']))
        try:
            run(['security', 'create-keychain', '-p', password, str(keychain)])
        finally:
            run(['security', 'list-keychains', '-d', 'user', '-s', *previous])
    run(['security', 'unlock-keychain', '-p', password, str(keychain)])
    previous = shlex.split(run(['security', 'list-keychains', '-d', 'user']))
    try:
        run(['security', 'list-keychains', '-d', 'user', '-s', *previous, str(keychain)])
        if not (STATE / 'imported').exists():
            archive = STATE / 'identity.p12'
            run(['openssl', 'pkcs12', '-export', '-legacy', '-inkey', str(STATE / 'private-key.pem'),
                 '-in', str(cert), '-out', str(archive), '-passout', 'file:' + str(password_file)])
            run(['security', 'import', str(archive), '-k', str(keychain), '-P', password, '-x', '-T', '/usr/bin/codesign'])
            (STATE / 'imported').touch()
            archive.unlink()
            (STATE / 'private-key.pem').unlink()
        fingerprint = run(['openssl', 'x509', '-in', str(cert), '-noout', '-fingerprint', '-sha1']).split('=')[1].replace(':', '')
        requirement = 'designated => identifier "com.johnbgood.localwriter" and certificate leaf = H"' + fingerprint + '"'
        run(['codesign', '--force', '--sign', fingerprint, '--keychain', str(keychain),
             '--timestamp=none', '--requirements', '=' + requirement, str(app)])
        run(['codesign', '--verify', '--strict', str(app)])
        print('Signed with persistent LocalWriter development certificate.')
    finally:
        run(['security', 'list-keychains', '-d', 'user', '-s', *previous])
        run(['security', 'lock-keychain', str(keychain)])

if __name__ == '__main__':
    try:
        main()
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
