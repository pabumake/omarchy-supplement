#!/bin/sh

set -eu

BROWSER="${ZEN_BROWSER_DESKTOP:-zen.desktop}"

set_default_browser() {
  if command -v xdg-settings >/dev/null 2>&1; then
    if xdg-settings set default-web-browser "$BROWSER"; then
      echo "Default browser set to $BROWSER via xdg-settings"
    else
      echo "Warning: failed to set default browser via xdg-settings"
    fi
  else
    echo "Warning: xdg-settings not found; skipping default browser change"
  fi
}

set_default_mime() {
  mime_type="$1"
  if xdg-mime default "$BROWSER" "$mime_type"; then
    echo "Set $mime_type default to $BROWSER"
  else
    echo "Warning: failed to set $mime_type default to $BROWSER"
  fi
}

if command -v xdg-mime >/dev/null 2>&1; then
  set_default_mime "x-scheme-handler/http"
  set_default_mime "x-scheme-handler/https"
  set_default_mime "text/html"
else
  echo "Warning: xdg-mime not found; skipping MIME defaults"
fi

set_default_browser
