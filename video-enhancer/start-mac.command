#!/usr/bin/env bash
# Starts the tool; installs Python 3 first if it is missing.
cd "$(dirname "$0")"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 not found - installing..."
  if command -v brew >/dev/null 2>&1; then brew install python
  elif command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y python3
  elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y python3
  elif command -v pacman >/dev/null 2>&1; then sudo pacman -S --noconfirm python
  elif [ "$(uname)" = "Darwin" ]; then xcode-select --install; echo "Run this script again after the install finishes."; exit 1
  else echo "Please install Python 3 from https://www.python.org/downloads/"; exit 1
  fi
fi
exec python3 -m enhancer "$@"
