#!/bin/sh

# there's a kernel extension so the Mac App Store is the most secure choice

if ! [ -d /Applications/Tailscale.app ]; then
  brewx mas install 1475387142
fi

exec /Applications/Tailscale.app/Contents/MacOS/Tailscale "$@"
