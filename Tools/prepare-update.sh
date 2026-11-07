#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ne 3 ]]; then
    printf 'Usage: %s archive.dmg https-download-url output.xml\n' "$0" >&2
    exit 1
fi
archive="$1"
url="$2"
output="$3"
[[ -f "$archive" && "$archive" == *.dmg && "$url" == https://* && "$output" == *.xml ]]
python3 - "$project_dir/Info.plist" "$archive" <<'PY'
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
expected = plistlib.loads(Path(sys.argv[1]).read_bytes())
with tempfile.TemporaryDirectory(prefix='edgeswipe-update-verify-') as directory:
    mount = Path(directory) / 'mounted'
    mount.mkdir()
    subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), '-plist', sys.argv[2]], check=True, stdout=subprocess.DEVNULL)
    try:
        applications = list(mount.glob('*.app/Contents/Info.plist'))
        assert len(applications) == 1, 'Expected one app in the update DMG'
        actual = plistlib.loads(applications[0].read_bytes())
        for key in ['CFBundleIdentifier', 'CFBundleVersion', 'CFBundleShortVersionString', 'SUPublicEDKey', 'SUFeedURL']:
            assert actual.get(key) == expected.get(key), 'Update archive mismatch: ' + key
    finally:
        subprocess.run(['hdiutil', 'detach', str(mount)], check=True, stdout=subprocess.DEVNULL)
print('Verified update archive identity, version, feed, and public key.')
PY
"$project_dir/Tools/prepare-sparkle-tools.sh"
key_file="$(swift "$project_dir/Tools/update-key.swift" --path)"
public_key="$(swift "$project_dir/Tools/update-key.swift")"
expected="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$project_dir/Info.plist")"
if [[ "$public_key" != "$expected" ]]; then
    printf 'The local signing key does not match SUPublicEDKey. Do not publish this update.\n' >&2
    exit 1
fi
signer="$project_dir/.build/sparkle-tools/distribution/bin/sign_update"
signature="$("$signer" --ed-key-file "$key_file" -p "$archive")"
"$signer" --ed-key-file "$key_file" --verify "$archive" "$signature"
python3 - "$project_dir/Info.plist" "$archive" "$url" "$output" "$signature" <<'PY'
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
import plistlib
import sys
import xml.etree.ElementTree as ET
info_path, archive, url, output, signature = sys.argv[1:]
info = plistlib.loads(Path(info_path).read_bytes())
sparkle = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', sparkle)
root = ET.Element('rss', version='2.0')
channel = ET.SubElement(root, 'channel')
ET.SubElement(channel, 'title').text = 'EdgeSwipe updates'
ET.SubElement(channel, 'link').text = 'https://github.com/winnercup1602/EdgeSwipe/releases'
ET.SubElement(channel, 'description').text = 'Signed EdgeSwipe releases'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = 'EdgeSwipe ' + info['CFBundleShortVersionString']
ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc))
for key, value in [('version', info['CFBundleVersion']), ('shortVersionString', info['CFBundleShortVersionString']), ('minimumSystemVersion', info['LSMinimumSystemVersion'])]:
    ET.SubElement(item, '{'+sparkle+'}'+key).text = value
ET.SubElement(item, 'enclosure', {'url': url, 'length': str(Path(archive).stat().st_size),
    'type': 'application/octet-stream', '{'+sparkle+'}edSignature': signature})
ET.indent(root)
Path(output).parent.mkdir(parents=True, exist_ok=True)
ET.ElementTree(root).write(output, encoding='utf-8', xml_declaration=True)
PY
"$signer" --ed-key-file "$key_file" "$output"
"$signer" --ed-key-file "$key_file" --verify "$output"
printf 'Signed and verified %s\n' "$output"
