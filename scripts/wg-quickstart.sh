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

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard qrencode iptables

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

systemctl enable --now wg-quick@wg0
wg show

echo "WireGuard server ready. Client example: /etc/wireguard/client-example.conf"
