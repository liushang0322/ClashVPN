#!/usr/bin/env bash
set -euo pipefail

# Tokyo server specific configuration
SERVER_PUBLIC_IP="101.36.117.231"
PUBLIC_IF="eth0"
WG_IF="wg0"
WG_PORT="51820"
WG_NETWORK_CIDR="10.66.66.0/24"
WG_SERVER_ADDR="10.66.66.1/24"
WG_DNS="1.1.1.1,8.8.8.8"

CLIENTS=(
  "phone1:10.66.66.2/32"
  "phone2:10.66.66.3/32"
  "pc1:10.66.66.4/32"
  "pc2:10.66.66.5/32"
)

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] 请用 root 运行：sudo bash $0" >&2
  exit 1
fi

if [[ ! -f /etc/os-release ]]; then
  echo "[ERROR] 无法识别系统版本。" >&2
  exit 1
fi

. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "[WARN] 当前不是 Ubuntu，脚本按 Ubuntu 24.04 编写，继续执行。"
fi

echo "[INFO] 安装 WireGuard 与依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y wireguard qrencode ufw

echo "[INFO] 开启 IP 转发..."
cat >/etc/sysctl.d/99-wireguard-forward.conf <<SYSCTL
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
SYSCTL
sysctl --system >/dev/null

mkdir -p /etc/wireguard /root/wg-clients
chmod 700 /etc/wireguard /root/wg-clients
umask 077

SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(printf '%s' "${SERVER_PRIV_KEY}" | wg pubkey)

WG_CONF="/etc/wireguard/${WG_IF}.conf"
cat >"${WG_CONF}" <<EOF_CONF
[Interface]
Address = ${WG_SERVER_ADDR}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
SaveConfig = false
PostUp = iptables -A FORWARD -i ${WG_IF} -j ACCEPT; iptables -A FORWARD -o ${WG_IF} -j ACCEPT; iptables -t nat -A POSTROUTING -s ${WG_NETWORK_CIDR} -o ${PUBLIC_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_IF} -j ACCEPT; iptables -D FORWARD -o ${WG_IF} -j ACCEPT; iptables -t nat -D POSTROUTING -s ${WG_NETWORK_CIDR} -o ${PUBLIC_IF} -j MASQUERADE
EOF_CONF

for client in "${CLIENTS[@]}"; do
  IFS=':' read -r client_name client_addr <<<"${client}"
  client_priv=$(wg genkey)
  client_pub=$(printf '%s' "${client_priv}" | wg pubkey)
  client_psk=$(wg genpsk)

  cat >>"${WG_CONF}" <<EOF_PEER

[Peer]
# ${client_name}
PublicKey = ${client_pub}
PresharedKey = ${client_psk}
AllowedIPs = ${client_addr}
EOF_PEER

  cat >"/root/wg-clients/${client_name}.conf" <<EOF_CLIENT
[Interface]
PrivateKey = ${client_priv}
Address = ${client_addr}
DNS = ${WG_DNS}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${client_psk}
Endpoint = ${SERVER_PUBLIC_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF_CLIENT

  chmod 600 "/root/wg-clients/${client_name}.conf"
done

chmod 600 "${WG_CONF}"

echo "[INFO] 配置 UFW 防火墙..."
ufw allow 22/tcp
ufw allow ${WG_PORT}/udp
ufw --force enable

echo "[INFO] 启动 WireGuard..."
systemctl enable wg-quick@${WG_IF}
systemctl restart wg-quick@${WG_IF}

echo "[INFO] 当前服务状态："
wg show "${WG_IF}" || true

echo
for client in "${CLIENTS[@]}"; do
  IFS=':' read -r client_name _ <<<"${client}"
  conf_file="/root/wg-clients/${client_name}.conf"
  echo "================ ${client_name} ================"
  echo "配置文件：${conf_file}"
  qrencode -t ansiutf8 <"${conf_file}" || true
  echo
done

echo "[DONE] 安装完成。可将 /root/wg-clients/*.conf 导入手机/电脑 WireGuard 客户端。"
