# WireGuard & Tailscale Quickstart (Ubuntu)

This repo documents a minimal, repeatable way to bring up a private network on Ubuntu using either **WireGuard** (self-hosted) or **Tailscale** (managed control plane on top of WireGuard). Both sections assume you have sudo access.

## WireGuard: fully self-hosted

### Install
```bash
sudo apt update
sudo apt install wireguard qrencode
```

### Generate keys
```bash
wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
wg genkey | tee /etc/wireguard/client.key | wg pubkey > /etc/wireguard/client.pub
chmod 600 /etc/wireguard/*.key
```

### Server config `/etc/wireguard/wg0.conf`
```ini
[Interface]
Address = 10.6.0.1/24
ListenPort = 51820
PrivateKey = <contents of /etc/wireguard/server.key>
# Enable IP forwarding
PostUp = sysctl -w net.ipv4.ip_forward=1
PostDown = sysctl -w net.ipv4.ip_forward=0

[Peer]
PublicKey = <contents of /etc/wireguard/client.pub>
AllowedIPs = 10.6.0.2/32
```

### Optional: internet egress/NAT
```bash
# replace <wan-interface> with your outbound NIC, e.g., eth0 or ens3
sudo iptables -t nat -A POSTROUTING -o <wan-interface> -j MASQUERADE
```
Persist with `iptables-persistent` or `netfilter-persistent` if needed. On systems that default to ufw, add the MASQUERADE rule
in `/etc/ufw/before.rules` and reload ufw so the rule survives reboots.

### Start & verify
```bash
sudo systemctl enable --now wg-quick@wg0
sudo wg show
```
If you ever need to temporarily stop forwarding, use `sudo systemctl stop wg-quick@wg0` (this also flushes the interface
address) and `sudo systemctl disable wg-quick@wg0` to prevent starting at boot.

### Client config example `client.conf`
```ini
[Interface]
Address = 10.6.0.2/24
PrivateKey = <contents of client.key>
DNS = 1.1.1.1

[Peer]
PublicKey = <contents of server.pub>
Endpoint = <server-public-ip>:51820
AllowedIPs = 0.0.0.0/0, ::/0    # use 10.6.0.0/24 for LAN-only
PersistentKeepalive = 25
```
Import into the WireGuard app (mobile/desktop). For phones, show a QR code:
```bash
qrencode -t ansiutf8 < client.conf
```

### Firewall checklist
- Open UDP 51820 on the server and any cloud security group.
- Ensure `net.ipv4.ip_forward=1` (set permanently in `/etc/sysctl.conf` if desired).

## Tailscale: managed control plane

### Install & log in
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh
```
The command opens a browser (or gives a URL) to authenticate with your Tailscale account.

### Status & IP
```bash
tailscale status
tailscale ip -4
```

### Subnet router (LAN access)
```bash
sudo tailscale up --ssh --advertise-routes=192.168.1.0/24
```
Approve the advertised route in the Tailscale admin console.

### Exit node (internet egress)
```bash
sudo tailscale up --ssh --advertise-exit-node
```
Enable "Use exit node" on clients.

### Access control
Manage ACLs, SSH, and tags from the Tailscale admin console. No port forwarding is required because NAT traversal is automatic.

## Quick troubleshooting
- Run `sudo wg show` or `tailscale status` to confirm peers.
- If WireGuard peers do not connect, re-check that UDP 51820 is reachable and that `AllowedIPs` match your planned topology.
- If traffic reaches the server but not the internet, confirm the MASQUERADE rule targets the correct outbound interface and
  that `net.ipv4.ip_forward` is set to 1 (`sudo sysctl net.ipv4.ip_forward`).
- If Tailscale subnet routing fails, verify the route is approved in the admin console and that the host can reach the LAN network.
- For either tool, check `journalctl -u wg-quick@wg0` or `sudo tailscale bugreport` for more detail.
