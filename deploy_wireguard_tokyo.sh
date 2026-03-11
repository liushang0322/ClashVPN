#!/usr/bin/env bash
set -euo pipefail

# Tokyo server specific configuration
SCRIPT_VERSION="2026-03-11.6"
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

echo "[INFO] 脚本版本: ${SCRIPT_VERSION}"

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

echo "[INFO] 配置 IP 转发（持久化）..."
SYSCTL_FILE="/etc/sysctl.d/99-wireguard-forward.conf"
cat >"${SYSCTL_FILE}" <<SYSCTL
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
SYSCTL

echo "[INFO] 已写入 ${SYSCTL_FILE}。"
# 尝试立即生效，失败时仅告警（常见于受限容器/LXC）
if sysctl -p "${SYSCTL_FILE}" >/dev/null 2>&1; then
  echo "[INFO] IP 转发已生效。"
else
  echo "[WARN] 无法立即启用 IP 转发（受限环境常见）。"
  echo "[WARN] 若客户端连上后无网络，请在宿主机/云主机层面开启 net.ipv4.ip_forward。"
fi

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
# 允许转发（否则常见症状是“客户端已连接但无网络”）
if [[ -f /etc/default/ufw ]]; then
  sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
fi
ufw allow 22/tcp
ufw allow ${WG_PORT}/udp
ufw route allow in on ${WG_IF} out on ${PUBLIC_IF}
ufw --force enable
ufw reload

echo "[INFO] 启动 WireGuard..."
systemctl enable wg-quick@${WG_IF}
systemctl restart wg-quick@${WG_IF}

echo "[INFO] 当前服务状态："
wg show "${WG_IF}" || true

QR_DIR="/root/wg-clients/qr"
mkdir -p "${QR_DIR}"
chmod 700 "${QR_DIR}"

echo
echo "[INFO] 客户端配置与二维码文件："
for client in "${CLIENTS[@]}"; do
  IFS=':' read -r client_name _ <<<"${client}"
  conf_file="/root/wg-clients/${client_name}.conf"
  qr_file="${QR_DIR}/${client_name}.png"
  qrencode -o "${qr_file}" -r "${conf_file}"
  chmod 600 "${qr_file}"

  echo "- ${client_name}:"
  echo "  conf: ${conf_file}"
  echo "  qr  : ${qr_file}"

  # 如需在终端显示二维码，执行：SHOW_QR_IN_TERMINAL=1 sudo ./deploy_wireguard_tokyo.sh
  if [[ "${SHOW_QR_IN_TERMINAL:-0}" == "1" ]]; then
    qrencode -t ansiutf8 <"${conf_file}" || true
    echo
  fi
done

ARCHIVE_FILE="/root/wg-clients/wg-clients-bundle.tar.gz"
tar -czf "${ARCHIVE_FILE}" -C /root wg-clients
chmod 600 "${ARCHIVE_FILE}"

echo "[INFO] PC 端推荐使用 .conf 文件导入（不依赖二维码）："
echo "       /root/wg-clients/phone1.conf"
echo "       /root/wg-clients/phone2.conf"
echo "       /root/wg-clients/pc1.conf"
echo "       /root/wg-clients/pc2.conf"
echo "[INFO] 已生成打包文件：${ARCHIVE_FILE}"
echo "[INFO] 可下载后在本地解压并导入 .conf。"

echo "[DONE] 安装完成。默认不在终端打印大二维码，避免刷屏。"
echo "[DONE] 可将 /root/wg-clients/*.conf 导入客户端，或使用 /root/wg-clients/qr/*.png 扫码导入。"


echo
echo "[CHECK] 部署后关键检查："
if sysctl net.ipv4.ip_forward 2>/dev/null | grep -q '= 1'; then
  echo "[OK] net.ipv4.ip_forward = 1"
else
  echo "[WARN] net.ipv4.ip_forward 不是 1，客户端可能连上但无网络。"
fi

if grep -q '^DEFAULT_FORWARD_POLICY="ACCEPT"' /etc/default/ufw 2>/dev/null; then
  echo "[OK] UFW DEFAULT_FORWARD_POLICY=ACCEPT"
else
  echo "[WARN] UFW 转发策略不是 ACCEPT。"
fi

if ufw status 2>/dev/null | grep -q "${WG_PORT}/udp"; then
  echo "[OK] UFW 已放行 ${WG_PORT}/udp"
else
  echo "[WARN] UFW 未看到 ${WG_PORT}/udp 放行规则。"
fi

if ufw status verbose 2>/dev/null | grep -qiE "route allow.*${WG_IF}.*${PUBLIC_IF}"; then
  echo "[OK] UFW route 转发规则已存在"
else
  echo "[WARN] 未检测到 UFW route 转发规则（wg0 -> ${PUBLIC_IF}）。"
fi

if iptables -t nat -S 2>/dev/null | grep -q "-A POSTROUTING -s ${WG_NETWORK_CIDR} -o ${PUBLIC_IF} -j MASQUERADE"; then
  echo "[OK] NAT MASQUERADE 规则已存在"
else
  echo "[WARN] 未检测到 NAT MASQUERADE 规则，可能尚未触发 wg-quick PostUp。"
fi

echo "[NEXT] 如果客户端仍无网络，请在服务器上执行："
echo "       sudo wg show ${WG_IF}"
echo "       sudo sysctl net.ipv4.ip_forward"
echo "       sudo ufw status verbose"
echo "       sudo iptables -t nat -S | grep MASQUERADE"
echo "[NEXT] 同时检查云厂商安全组已放行 UDP ${WG_PORT}。"
