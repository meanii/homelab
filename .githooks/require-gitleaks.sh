# Sourced by the hooks. Fails closed: no scanner, no commit/push.
if ! command -v gitleaks >/dev/null 2>&1; then
	cat >&2 <<'EOF'
gitleaks is not installed, so this hook cannot check for secrets. Install it:

  v=8.30.1
  curl -fsSLO https://github.com/gitleaks/gitleaks/releases/download/v$v/gitleaks_${v}_linux_x64.tar.gz
  tar -xzf gitleaks_${v}_linux_x64.tar.gz gitleaks && install -m755 gitleaks ~/.local/bin/

(macOS: brew install gitleaks)
EOF
	exit 1
fi
