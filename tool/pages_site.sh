#!/bin/bash
# Copies site/ into a GitHub Pages tree ($1, default pages-site/) and rewires
# it for https://agent.langshen.xyz — the site is written for a domain root,
# and the custom domain serves it at one. Manifest fetches go to the Pages
# latest.json files langshen-release.yml publishes, /dl/* links to the
# GitHub releases (site.js rewrites data-file anchors from the manifest
# anyway; these are the no-JS fallbacks).
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/pages-site}"
mkdir -p "$out"
cp -R "$root/site/." "$out/"

pages=""
releases="https://github.com/DuZunTianXia/langshenagent/releases"
manifests="https://agent.langshen.xyz/releases"
files=$(find "$out" -name '*.html' -o -name '*.js' -o -name '*.css')

# The manifests' and the framed-channel fallback's hosts.
sed -i '' \
  -e "s|https://dl\.langshenagent\.dev/releases/|$manifests/|g" \
  -e "s|https://langshenagent\.dev/dl/|$releases/|g" \
  -e "s|https://langshenagent\.dev/|https://agent.langshen.xyz/|g" \
  $files

# /dl/<target> links: site.js rewrites data-file ones from the manifest;
# the rest fall back to the releases page.
sed -i '' \
  -e "s|\"/dl/[^\"]*\"|\"$releases\"|g" \
  -e "s|'/dl/[^']*'|'$releases'|g" \
  $files

# Root-absolute references to /langshenagent-absolute ones.
sed -i '' \
  -e "s|href=\"/|href=\"$pages/|g" \
  -e "s|src=\"/|src=\"$pages/|g" \
  -e "s|action=\"/|action=\"$pages/|g" \
  -e "s|poster=\"/|poster=\"$pages/|g" \
  -e "s|url(/|url($pages/|g" \
  $files
# Single-quoted URL constants in the scripts (known prefixes only: a blanket
# '/ -> '/langshenagent/ rewrite would corrupt strings like split('/')).
sed -i '' \
  -e "s|'/channels.json'|'$pages/channels.json'|g" \
  -e "s|'/brand/|'$pages/brand/|g" \
  -e "s|'/icon.png'|'$pages/icon.png'|g" \
  -e "s|'/zh/'|'$pages/zh/'|g" \
  -e "s|'/zh'|'$pages/zh'|g" \
  $files

# Pages does no extensionless serving: /x and /zh/x become x.html.
for page in download changelog browser-privacy mobile-privacy upstreams \
            activate import push; do
  sed -i '' \
    -e "s|\"$pages/$page\"|\"$pages/$page.html\"|g" \
    -e "s|\"$pages/$page#|\"$pages/$page.html#|g" \
    -e "s|\"$pages/zh/$page\"|\"$pages/zh/$page.html\"|g" \
    -e "s|\"$pages/zh/$page#|\"$pages/zh/$page.html#|g" \
    $files
done
# The bare /zh link gets its trailing slash back.
sed -i '' "s|\"$pages/zh\"|\"$pages/zh/\"|g" $files

# Direct-download hrefs baked into the HTML from the published manifests:
# site.js still upgrades them live, but a click before it does — or with
# no JavaScript — already downloads the file, not the releases page.
tmp="$(mktemp -d)"
# The manifest already in $out wins — publish signs it before this runs,
# so the links are the release being published, not the one before.
latest="$out/releases/latest.json"
mobile="$out/releases/mobile/latest.json"
[ -f "$latest" ] || { latest="$tmp/latest.json"; curl -fsS --max-time 20 "$manifests/latest.json" -o "$latest" 2>/dev/null || latest=; }
[ -f "$mobile" ] || { mobile="$tmp/mobile.json"; curl -fsS --max-time 20 "$manifests/mobile/latest.json" -o "$mobile" 2>/dev/null || mobile=; }
[ -n "$latest$mobile" ] && python3 - "$latest" "$mobile" "$releases" "$out" <<'PY'
import json, re, sys, urllib.parse

latest_path, mobile_path, releases, out = sys.argv[1:5]
urls = {}
if latest_path:
    try:
        downloads = json.load(open(latest_path)).get('downloads') or {}
        for name, file in downloads.items():
            if isinstance(file, dict) and file.get('url'):
                urls[name] = file['url']
    except Exception:
        pass
if mobile_path:
    try:
        apk = json.load(open(mobile_path)).get('apk', '')
        url = apk if apk.startswith('http') else f'{releases}/download{apk}'
        urls['android'] = urls['androidArm64'] = url
    except Exception:
        pass
if not urls:
    sys.exit(0)

import pathlib
anchor = re.compile(r'<a\b[^>]*data-file="([^"]+)"[^>]*>')
href = re.compile(r'href="[^"]*"')
for page in pathlib.Path(out).rglob('*.html'):
    text = page.read_text(encoding='utf-8')
    def swap(match):
        url = urls.get(match.group(1))
        return href.sub(f'href="{url}"', match.group(0), count=1) if url else match.group(0)
    page.write_text(anchor.sub(swap, text), encoding='utf-8')
PY
rm -rf "$tmp"
