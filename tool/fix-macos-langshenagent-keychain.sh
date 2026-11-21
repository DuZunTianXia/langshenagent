#!/bin/sh
# Clears stuck LangshenAgent generic passwords and fixes the user keychain search
# list when Key save fails with -25299 / "item already exists".
set -e
LOGIN="${HOME}/Library/Keychains/login.keychain-db"
echo "Default keychain: $(security default-keychain -d user 2>/dev/null || true)"
# Never shrink the search list to login alone — Local Items (keychain-2.db)
# holds most third-party credentials on modern macOS.
LOCAL="$(find "${HOME}/Library/Keychains" -maxdepth 2 -name keychain-2.db 2>/dev/null | head -1)"
if [ -n "$LOCAL" ] && [ "$LOCAL" != "$LOGIN" ]; then
  echo "Search list: login + Local Items…"
  security list-keychains -d user -s "$LOGIN" "$LOCAL"
else
  echo "Search list: login only (no Local Items keychain found)…"
  security list-keychains -d user -s "$LOGIN"
fi
KC="$LOGIN"
n=0
while security delete-generic-password -s LangshenAgent "$KC" 2>/dev/null; do
  n=$((n + 1))
done
echo "Removed $n LangshenAgent password item(s) from login keychain."
echo "Quit LangshenAgent, reopen it, then enter your API keys again."