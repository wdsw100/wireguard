#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

TS_ARGS=(--ssh)
if [[ -n "${TS_AUTHKEY:-}" ]]; then
  TS_ARGS+=("--authkey=${TS_AUTHKEY}")
fi
if [[ -n "${TS_ADVERTISE_ROUTES:-}" ]]; then
  TS_ARGS+=("--advertise-routes=${TS_ADVERTISE_ROUTES}")
fi
if [[ "${TS_ADVERTISE_EXIT:-0}" == "1" ]]; then
  TS_ARGS+=("--advertise-exit-node")
fi

# Bring the node online. If no authkey is provided, this will print a URL
# for you to open in a browser to authenticate.
tailscale up "${TS_ARGS[@]}"

tailscale status
tailscale ip -4

echo "Tailscale is up. Manage ACLs and routes from the admin console."
