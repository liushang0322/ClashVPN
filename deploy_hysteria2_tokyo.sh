#!/usr/bin/env bash
set -euo pipefail

# Hysteria2 parallel deployment for Tokyo server
HY2_PORT="8443"
HY2_DOMAIN_FALLBACK="www.microsoft.com"
HY2_UP_BW="30 mbps"
HY2_DOWN_BW="30 mbps"

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] 请使用 root 运行：sudo bash $0" >&2
  exit 1
fi

echo "[INFO] 安装依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl openssl ufw ca-certificates

ARCH_RAW="$(uname -m)"
case "${ARCH_RAW}" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "[ERROR] 不支持的架构: ${ARCH_RAW}" >&2
    exit 1
    ;;
esac

LATEST_TAG="$(curl -fsSL https://api.github.com/repos/apernet/hysteria/releases/latest | sed -n 's/.*"tag_name": "\(v[^"]*\)".*/\1/p' | head -n1)"
if [[ -z "${LATEST_TAG}" ]]; then
  echo "[ERROR] 无法获取 Hysteria2 最新版本。" >&2
  exit 1
fi

echo "[INFO] 下载 Hysteria2 ${LATEST_TAG} (${ARCH})..."
BIN_URL="https://github.com/apernet/hysteria/releases/download/${LATEST_TAG}/hysteria-linux-${ARCH}"
curl -fL "${BIN_URL}" -o /usr/local/bin/hysteria
chmod +x /usr/local/bin/hysteria

if ! id -u hysteria >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin hysteria
fi

PUBLIC_IP="$(curl -4 -fsSL ifconfig.me || true)"
if [[ -z "${PUBLIC_IP}" ]]; then
  PUBLIC_IP="$(hostname -I | awk '{print $1}')"
fi

PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 22)"
OBFS_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 22)"

mkdir -p /etc/hysteria/certs
chmod 700 /etc/hysteria /etc/hysteria/certs

echo "[INFO] 生成自签证书..."
openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
  -keyout /etc/hysteria/certs/server.key \
  -out /etc/hysteria/certs/server.crt \
  -subj "/CN=${PUBLIC_IP}" >/dev/null 2>&1
chmod 600 /etc/hysteria/certs/server.key /etc/hysteria/certs/server.crt

cat >/etc/hysteria/config.yaml <<CFG
listen: :${HY2_PORT}

tls:
  cert: /etc/hysteria/certs/server.crt
  key: /etc/hysteria/certs/server.key

auth:
  type: password
  password: ${PASSWORD}

obfs:
  type: salamander
  salamander:
    password: ${OBFS_PASS}

masquerade:
  type: proxy
  proxy:
    url: https://${HY2_DOMAIN_FALLBACK}

bandwidth:
  up: ${HY2_UP_BW}
  down: ${HY2_DOWN_BW}
CFG
chmod 600 /etc/hysteria/config.yaml

cat >/etc/systemd/system/hysteria-server.service <<'UNIT'
[Unit]
Description=Hysteria2 Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=hysteria
Group=hysteria
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=3
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now hysteria-server

echo "[INFO] 开放防火墙端口..."
ufw allow 22/tcp || true
ufw allow ${HY2_PORT}/udp
ufw --force enable
ufw reload

URI="hy2://${PASSWORD}@${PUBLIC_IP}:${HY2_PORT}/?insecure=1&sni=${HY2_DOMAIN_FALLBACK}&obfs=salamander&obfs-password=${OBFS_PASS}#Tokyo-Hysteria2"

mkdir -p /root/hy2-clients
chmod 700 /root/hy2-clients
printf '%s\n' "${URI}" >/root/hy2-clients/hy2-uri.txt
chmod 600 /root/hy2-clients/hy2-uri.txt

echo
echo "================= Hysteria2 部署完成 ================="
echo "服务状态:"
systemctl --no-pager --full status hysteria-server | sed -n '1,12p' || true
echo
echo "连接信息（可直接复制到支持 Hysteria2 的客户端）："
echo "${URI}"
echo
echo "已保存到: /root/hy2-clients/hy2-uri.txt"
echo "======================================================="
