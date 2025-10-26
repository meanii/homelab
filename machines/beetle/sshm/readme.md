# sshm 
> sshm is ssh tunnel daemon

## install
installing sshm is easy, just run the following command:

1. create sshm daemon
```bash
sudo cat << EOF > /etc/systemd/system/sshm.service
[Unit]
Description=sshm ssh tunnel daemon

[Service]
Type=simple
User=meanii
ExecStart=/etc/sshm.sh

[Install]
WantedBy=multi-user.target
EOF
```

2. create sshm script
```bash
sudo cat << EOF > /etc/sshm.sh
#!/bin/bash 

# author: meanii (https://github.com/meanii)
# This script is run on the remote server to set up the reverse tunnel
# It is run as root

ssh -nNTv -R 0.0.0.0:2222:localhost:22 root@meanii.dev
EOF
```

3. grant permissions
```bash
sudo chmod +x /etc/sshm.sh
```

4. reload daemon
```bash
sudo systemctl daemon-reload
```

5. enable sshm and start
```bash
sudo systemctl enable sshm --now
```

## configure server
On that VPS, I needed to configure SSH so it could work as a tunnel server:

SSH's `AllowTCPForwarding` option must be set to yes for this to work—and that's the default. But you can confirm this with sshd -T.

You will need to configure the `GatewayPorts` option, so edit the SSH config file:
```bash
sudo vim /etc/ssh/sshd_config
```
and set `GatewayPorts` to `yes`:
```bash
GatewayPorts yes
AllowTCPForwarding yes
```
and restart the SSH server:
```bash
sudo systemctl restart sshd
```

Confirm both settings are yes with:
```bash
sshd -T | grep -E 'gatewayports|allowtcpforwarding'
gatewayports yes
allowtcpforwarding yes
```
> Security Warning: For better security, you can set GatewayPorts clientspecified, and then specify certain IP addresses allowed to connect. Or, you could restrict access to localhost by setting GatewayPorts no—that way only users who are logged into the tunnel server could access the Raspberry Pi via SSH.

## usage
```bash
ssh -p 2222 [USER]@[HOST]
```
## troubleshooting
There are a few things that could be going wrong:
- Check SSH's current configuration with `sshd -T | grep -E 'gatewayports|allowtcpforwarding'` — make sure the two settings configured correctly. If the sshd config file is correct, make sure you restart SSH to make the changes take effect (`sudo systemctl restart ssh`).
- If you have a firewall configured on the server (iptables, nftables, ufw, or firewalld), make sure the ports are open through which you're connecting!
- Triple check open connections with `netstat -tulpn` — in one case, I hadn't set GatewayPorts correctly, so when I ran that command, I saw a listing for 127.0.0.1:2222, meaning the forwarded port was only accessible if logged directly into the VPS. It should be showing as 0.0.0.0:2222 if you set up everything according to this guide.
