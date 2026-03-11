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
- 终端二维码：可直接在 WireGuard 手机端扫码导入

## 客户端导入

- 手机：安装 WireGuard App，扫终端二维码导入。
- 电脑：WireGuard 客户端导入 `/root/wg-clients/pc1.conf` 或 `/root/wg-clients/pc2.conf`。

## 常用命令

```bash
sudo systemctl status wg-quick@wg0
sudo wg show wg0
sudo systemctl restart wg-quick@wg0
```

## 安全建议

- 强烈建议 SSH 关闭密码登录，仅保留密钥登录。
- 建议定期更新系统：`sudo apt update && sudo apt upgrade -y`。
