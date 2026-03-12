# ClashVPN WireGuard 部署脚本（东京服务器）

此仓库提供了针对以下固定参数的一键部署脚本：

- 系统：Ubuntu 24.04 LTS
- 服务器公网 IP：`101.36.117.231`
- 网卡：`eth0`
- 协议：WireGuard（UDP 51820）
- 客户端：4 个（`phone1`、`phone2`、`pc1`、`pc2`）
- VPN 网段：`10.66.66.0/24`
- 防火墙：自动放行 `22/tcp`、`51820/udp`（UFW）

## 使用方式

```bash
chmod +x deploy_wireguard_tokyo.sh
sudo ./deploy_wireguard_tokyo.sh
```

执行后会生成：

- 服务端配置：`/etc/wireguard/wg0.conf`
- 客户端配置：`/root/wg-clients/*.conf`
- PNG 二维码：`/root/wg-clients/qr/*.png` 可直接扫码导入（默认不再终端刷屏）
- PC/文件导入包：`/root/wg-clients/wg-clients-bundle.tar.gz`（含全部 `.conf` 与 `qr/`）

## 受限环境说明（你遇到的 sysctl 报错）

如果你在容器或受限虚拟化环境中运行，可能看到：

- `sysctl: setting key "net.ipv4.ip_forward": Operation not permitted`

这通常是宿主机限制，不是脚本语法问题。脚本会写入 `/etc/sysctl.d/99-wireguard-forward.conf`，并尝试 `sysctl -p` 立即生效；若环境受限则给出告警并继续。


## 如果仍看到 `vm.max_map_count` 之类 sysctl 报错

这代表你运行的还是旧脚本（旧版会使用 `sysctl --system`）。
当前脚本启动时会打印版本号，并且不会执行 `sysctl --system`（仅针对 WireGuard 配置文件尝试 `sysctl -p`）。

可用下面命令确认：

```bash
grep -n "sysctl --system" deploy_wireguard_tokyo.sh || echo "OK: no sysctl --system"
head -n 20 deploy_wireguard_tokyo.sh
```


如果你仍希望在终端直接打印二维码，可临时开启：

```bash
SHOW_QR_IN_TERMINAL=1 sudo ./deploy_wireguard_tokyo.sh
```

## 客户端导入

- 手机：安装 WireGuard App，优先扫描 `/root/wg-clients/qr/*.png`。
- 电脑（推荐）：WireGuard 客户端使用“从文件导入隧道”，导入 `/root/wg-clients/*.conf`。
- 如果需要一次性下载到本地：先下载 `/root/wg-clients/wg-clients-bundle.tar.gz`，解压后导入 `.conf` 文件。

示例（在你本地电脑执行）：

```bash
scp root@101.36.117.231:/root/wg-clients/wg-clients-bundle.tar.gz .
tar -xzf wg-clients-bundle.tar.gz
```

## 常用命令

```bash
sudo systemctl status wg-quick@wg0
sudo wg show wg0
sudo systemctl restart wg-quick@wg0
```

## 安全建议

- 强烈建议 SSH 关闭密码登录，仅保留密钥登录。
- 建议定期更新系统：`sudo apt update && sudo apt upgrade -y`。



## 你现在需要做什么（最短路径）

1. 在服务器重新执行一遍脚本：

```bash
sudo ./deploy_wireguard_tokyo.sh
```

2. 脚本末尾会打印 `[CHECK]` 自检结果。请确认至少这 5 项为 OK：
   - `net.ipv4.ip_forward = 1`
   - `UFW DEFAULT_FORWARD_POLICY=ACCEPT`
   - `UFW 已放行 51820/udp`
   - `UFW route 转发规则已存在`
   - `NAT MASQUERADE 规则已存在`

3. 若手机仍“已连接但没网”，把这 4 条命令输出发我：

```bash
sudo wg show wg0
sudo sysctl net.ipv4.ip_forward
sudo ufw status verbose
sudo iptables -t nat -S | grep MASQUERADE
```

4. 最后确认云厂商安全组：
   - 入站放行 `UDP 51820`
   - 出站允许全部（或至少 DNS/HTTP/HTTPS）

## 常见问题：手机显示已连接，但没有网络

> 说明：如果你曾看到 `grep: ... invalid context length argument`，这是旧版本脚本的 NAT 检查误报，升级到最新版后已修复。


请按下面顺序检查：

```bash
# 1) 查看服务是否正常
sudo wg show wg0
sudo systemctl status wg-quick@wg0 --no-pager

# 2) 查看内核转发
sysctl net.ipv4.ip_forward

# 3) 查看 UFW 转发策略和路由放行
grep -n '^DEFAULT_FORWARD_POLICY' /etc/default/ufw
sudo ufw status verbose

# 4) 查看 NAT 规则是否存在
sudo iptables -t nat -S | grep MASQUERADE
```

预期关键点：
- `net.ipv4.ip_forward = 1`
- `DEFAULT_FORWARD_POLICY="ACCEPT"`
- `ufw status` 里有 `51820/udp` 和 `route allow in on wg0 out on eth0`



## 无法通过 scp 时：使用 Git 中转传输（建议加密）

可以，但**不要把明文 `.conf` 直接提交到 Git 仓库**（里面有私钥）。

推荐做法：在服务器上先加密，再通过 Git/网盘中转。

### 服务器上（打包并加密）

```bash
cd /root/wg-clients
sudo tar -czf /root/wg-clients-bundle.tar.gz .
# 交互输入加密口令
sudo openssl enc -aes-256-cbc -pbkdf2 -salt \
  -in /root/wg-clients-bundle.tar.gz \
  -out /root/wg-clients-bundle.tar.gz.enc
```

### 用 Git 中转（示例）

```bash
# 在服务器上
mkdir -p ~/wg-transfer && cd ~/wg-transfer
git init
git checkout -b main
cp /root/wg-clients-bundle.tar.gz.enc .
git add wg-clients-bundle.tar.gz.enc
git commit -m "add encrypted wireguard bundle"
# 添加你自己的私有仓库后 push
# git remote add origin <your-private-repo-url>
# git push -u origin main
```

### 本地电脑（下载并解密）

```bash
git clone <your-private-repo-url>
cd <repo-dir>
openssl enc -d -aes-256-cbc -pbkdf2 \
  -in wg-clients-bundle.tar.gz.enc \
  -out wg-clients-bundle.tar.gz
tar -xzf wg-clients-bundle.tar.gz
```

> 如果你不想走 Git，也可以把 `wg-clients-bundle.tar.gz.enc` 上传到临时网盘，再在本地下载解密。



## 下载失败排障（你截图里的两类错误）

### 1) `scp ... port 22: Connection timed out`

这表示**网络层到服务器 22 端口不通**（不是账号/密码问题）。

请在服务器控制台（VNC）确认：

```bash
sudo systemctl status ssh --no-pager
sudo ss -lntp | grep :22
sudo ufw status verbose
```

再到云厂商控制台确认安全组：

- 入站必须放行 `TCP 22`（建议先临时放开 `0.0.0.0/0` 测试）
- 入站放行 `UDP 51820`（WireGuard）

在 Windows 本地先测连通性：

```powershell
Test-NetConnection 101.36.117.231 -Port 22
```

如果你自定义了 SSH 端口（比如 2222），下载要用：

```bash
scp -P 2222 root@101.36.117.231:/root/wg-clients/wg-clients-bundle.tar.gz .
```

### 2) `openssl ... Verify failure / bad password read`

这通常是交互输入两次口令不一致，或命令未带 `-in/-out` 参数完整执行。

建议直接用**非交互口令参数**（避免输入两次出错）：

```bash
# 在服务器上加密（把 YourStrongPass 改成你的强口令）
sudo openssl enc -aes-256-cbc -pbkdf2 -salt   -pass pass:'YourStrongPass'   -in /root/wg-clients/wg-clients-bundle.tar.gz   -out /root/wg-clients/wg-clients-bundle.tar.gz.enc
```

本地解密：

```bash
openssl enc -d -aes-256-cbc -pbkdf2   -pass pass:'YourStrongPass'   -in wg-clients-bundle.tar.gz.enc   -out wg-clients-bundle.tar.gz
```

> 口令里如果有特殊字符，请用单引号包裹；或改用纯字母数字强口令。



## 可选：并行部署 Hysteria2（用于对比速度）

如果你想和 WireGuard 做 A/B 速度对比，可执行：

```bash
chmod +x deploy_hysteria2_tokyo.sh
sudo ./deploy_hysteria2_tokyo.sh
```

脚本会输出一条 `hy2://` URI，并保存到：

- `/root/hy2-clients/hy2-uri.txt`

该脚本为并行部署，不会覆盖现有 WireGuard 配置。

