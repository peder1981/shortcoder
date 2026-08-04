#!/usr/bin/env bash
# Instala o shortcoder baixando o binário certo do último release no GitHub.
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/peder1981/shortcoder/master/install.sh | bash
set -euo pipefail

REPO="peder1981/shortcoder"
INSTALL_DIR="${SHORTCODER_INSTALL_DIR:-$HOME/.local/bin}"

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Linux)
    asset="shortcoder-linux-amd64.tar.gz"
    bin="shortcoder-linux-amd64"
    ;;
  Darwin)
    if [ "$arch" != "arm64" ]; then
      echo "Erro: build oficial de macOS é só para Apple Silicon (arm64). Compile localmente com 'advplc build'." >&2
      exit 1
    fi
    asset="shortcoder-macos-arm64.tar.gz"
    bin="shortcoder-macos-arm64"
    ;;
  *)
    echo "Erro: plataforma não suportada: $os. Use o Windows via shortcoder-windows-amd64.zip manualmente." >&2
    exit 1
    ;;
esac

url="https://github.com/$REPO/releases/latest/download/$asset"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "Baixando $asset..."
curl -fsSL "$url" -o "$tmpdir/$asset"

tar -xzf "$tmpdir/$asset" -C "$tmpdir"

mkdir -p "$INSTALL_DIR"
mv "$tmpdir/$bin" "$INSTALL_DIR/shortcoder"
chmod +x "$INSTALL_DIR/shortcoder"

echo "shortcoder instalado em $INSTALL_DIR/shortcoder"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "Adicione ao PATH: export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
esac
