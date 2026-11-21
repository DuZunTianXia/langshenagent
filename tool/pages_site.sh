#!/bin/bash
# Copies site/ into a GitHub Pages tree ($1, default pages-site/) and rewires
# it for https://duzuntianxia.github.io/baocode — the site is written for a
# domain root, Pages serves it under /baocode/. Manifest fetches go to the
# Pages latest.json files langshen-release.yml publishes, /dl/* links to the
# GitHub releases (site.js rewrites data-file anchors from the manifest
# anyway; these are the no-JS fallbacks).
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/pages-site}"
mkdir -p "$out"
cp -R "$root/site/." "$out/"

pages="/baocode"
releases="https://github.com/DuZunTianXia/baocode/releases"
manifests="https://duzuntianxia.github.io/baocode/releases"
files=$(find "$out" -name '*.html' -o -name '*.js' -o -name '*.css')

# The manifests' and the framed-channel fallback's hosts.
sed -i '' \
  -e "s|https://dl\.langshenagent\.dev/releases/|$manifests/|g" \
  -e "s|https://langshenagent\.dev/dl/|$releases/|g" \
  -e "s|https://langshenagent\.dev/|https://duzuntianxia.github.io/baocode/|g" \
  $files

# /dl/<target> links: site.js rewrites data-file ones from the manifest;
# the rest fall back to the releases page.
sed -i '' \
  -e "s|\"/dl/[^\"]*\"|\"$releases\"|g" \
  -e "s|'/dl/[^']*'|'$releases'|g" \
  $files

# Root-absolute references to /baocode-absolute ones.
sed -i '' \
  -e "s|href=\"/|href=\"$pages/|g" \
  -e "s|src=\"/|src=\"$pages/|g" \
  -e "s|action=\"/|action=\"$pages/|g" \
  -e "s|poster=\"/|poster=\"$pages/|g" \
  -e "s|url(/|url($pages/|g" \
  $files
# Single-quoted URL constants in the scripts (known prefixes only: a blanket
# '/ -> '/baocode/ rewrite would corrupt strings like split('/')).
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
