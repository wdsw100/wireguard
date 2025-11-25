#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

WG_SERVER_ADDR=${WG_SERVER_ADDR:-10.6.0.1/24}
WG_CLIENT_ADDR=${WG_CLIENT_ADDR:-10.6.0.2/32}
WG_PORT=${WG_PORT:-51820}
WG_WAN_IFACE=${WG_WAN_IFACE:-}
WG_CLIENT_INTERFACE_ADDR=${WG_CLIENT_INTERFACE_ADDR:-10.6.0.2/24}
WG_CLIENT_ALLOWED=${WG_CLIENT_ALLOWED:-"0.0.0.0/0, ::/0"}
WG_ENDPOINT=${WG_ENDPOINT:-"<server-public-ip>:${WG_PORT}"}
# start method: systemd (default when available), wg-quick, or none
WG_START_METHOD=${WG_START_METHOD:-auto}

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard qrencode iptables iproute2

mkdir -p /etc/wireguard
cd /etc/wireguard
umask 077

if [[ ! -f server.key ]]; then
  wg genkey | tee server.key | wg pubkey > server.pub
fi

if [[ ! -f client.key ]]; then
  wg genkey | tee client.key | wg pubkey > client.pub
fi

POST_UP="sysctl -w net.ipv4.ip_forward=1"
POST_DOWN="sysctl -w net.ipv4.ip_forward=0"
if [[ -n "$WG_WAN_IFACE" ]]; then
  POST_UP+="; iptables -t nat -A POSTROUTING -o ${WG_WAN_IFACE} -j MASQUERADE"
  POST_DOWN+="; iptables -t nat -D POSTROUTING -o ${WG_WAN_IFACE} -j MASQUERADE"
fi

cat > wg0.conf <<EOF_CFG
[Interface]
Address = ${WG_SERVER_ADDR}
ListenPort = ${WG_PORT}
PrivateKey = $(cat server.key)
PostUp = ${POST_UP}
PostDown = ${POST_DOWN}

[Peer]
PublicKey = $(cat client.pub)
AllowedIPs = ${WG_CLIENT_ADDR}
EOF_CFG

cat > client-example.conf <<EOF_CFG
[Interface]
Address = ${WG_CLIENT_INTERFACE_ADDR}
PrivateKey = $(cat client.key)
DNS = 1.1.1.1

[Peer]
PublicKey = $(cat server.pub)
Endpoint = ${WG_ENDPOINT}
AllowedIPs = ${WG_CLIENT_ALLOWED}
PersistentKeepalive = 25
EOF_CFG

bring_up() {
  ensure_kernel_support() {
    if command -v modprobe >/dev/null 2>&1 && modprobe wireguard 2>/dev/null; then
      return 0
    fi
    if command -v lsmod >/dev/null 2>&1 && lsmod | grep -q '^wireguard'; then
      return 0
    fi
    echo "WireGuard kernel module not available; install wireguard-dkms or upgrade your kernel." >&2
    return 1
  }

  is_systemd_available() {
    [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1
  }

  case "${1}" in
    none)
      echo "Skipping bring-up (WG_START_METHOD=none)."
      ;;
    systemd|auto)
      if ! ensure_kernel_support; then
        echo "Skipping bring-up; kernel support is missing." >&2
        return
      fi
      if is_systemd_available; then
        systemctl enable --now wg-quick@wg0
        return
      elif [[ "${1}" == "systemd" ]]; then
        echo "systemd requested but unavailable; falling back to wg-quick up." >&2
      fi
      ;;&
    wg-quick|auto)
      if ensure_kernel_support; then
        wg-quick up wg0
      else
        echo "Skipping bring-up; kernel support is missing." >&2
      fi
      ;;
    *)
      echo "Unknown WG_START_METHOD: ${1}" >&2
      exit 1
      ;;
  esac
}

bring_up "${WG_START_METHOD}"
wg show

echo "WireGuard server ready. Client example: /etc/wireguard/client-example.conf"
