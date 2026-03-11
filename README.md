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

