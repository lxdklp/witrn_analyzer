"""Restore GitHub Actions signing secrets without logging their values."""
import base64
import os
from pathlib import Path


def escape_property(value: str) -> str:
    return (value.replace('\\', '\\\\').replace('\n', '\\n')
            .replace('\r', '\\r').replace('\t', '\\t').replace(' ', '\\ '))


def main() -> None:
    names = ('ANDROID_KEYSTORE_BASE64', 'ANDROID_STORE_PASSWORD',
             'ANDROID_KEY_PASSWORD', 'ANDROID_KEY_ALIAS')
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        raise SystemExit('Missing GitHub Actions secrets: ' + ', '.join(missing))
    android = Path(__file__).resolve().parents[1] / 'android'
    keystore = android / 'signing/ci-keystore.jks'
    properties = android / 'key.properties'
    if keystore.exists() or properties.exists():
        raise SystemExit('Refusing to overwrite existing Android signing files.')
    # Validate the entire base64 value before writing any files.
    data = base64.b64decode(''.join(os.environ[names[0]].split()), validate=True)
    if not data:
        raise SystemExit('Empty keystore.')
    os.umask(0o077)
    keystore.parent.mkdir(parents=True, exist_ok=True)
    keystore.write_bytes(data)
    values = {
        'storeFile': 'signing/ci-keystore.jks',
        'storePassword': os.environ['ANDROID_STORE_PASSWORD'],
        'keyPassword': os.environ['ANDROID_KEY_PASSWORD'],
        'keyAlias': os.environ['ANDROID_KEY_ALIAS'],
    }
    properties.write_text(''.join(f'{key}={escape_property(value)}\n'
                                  for key, value in values.items()), encoding='utf-8')


if __name__ == '__main__':
    main()
