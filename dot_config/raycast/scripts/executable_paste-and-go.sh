#!/bin/zsh

# @raycast.schemaVersion 1
# @raycast.title Paste and Go
# @raycast.mode silent
# @raycast.packageName Navigation
# @raycast.icon 🌐
# @raycast.description Open a clipboard URL or search its text with Google

value="$(pbpaste)"

case "$value" in
  *://*)
    open "$value"
    ;;
  *)
    query="$(/usr/bin/osascript -l JavaScript \
      -e 'function run(argv) { return encodeURIComponent(argv[0]); }' "$value")"
    open "https://www.google.com/search?q=$query"
    ;;
esac
