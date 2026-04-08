#!/bin/bash
# 阿里云 Nginx SSL+代理/主站 极简脚本
# 公用邮箱：public@acme.ssl
# 要求：已装Nginx、域名解析、放行80/443

[ "$(id -u)" != "0" ] && echo "请root执行" && exit 1
command -v nginx >/dev/null 2>&1 || { echo "未安装Nginx"; exit 1; }

# 固定公用邮箱
EMAIL="public@acme.ssl"

read -p "域名: " DOMAIN

echo "1=反向代理 2=主站"
read -p "模式: " MODE

# 系统默认目录
[ -f /etc/redhat-release ] && WEB_ROOT="/usr/share/nginx/html" || WEB_ROOT="/var/www/html"

# 安装acme
curl https://get.acme.sh | sh -s email=$EMAIL >/dev/null 2>&1
source ~/.bashrc
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1

# 签发证书
systemctl stop nginx
~/.acme.sh/acme.sh --issue -d $DOMAIN --nginx --force >/dev/null 2>&1

# 生成配置
cat > /etc/nginx/conf.d/$DOMAIN.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $DOMAIN;
    ssl_certificate /root/.acme.sh/$DOMAIN/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/$DOMAIN/$DOMAIN.key;
    ssl_protocols TLSv1.2 TLSv1.3;
EOF

if [ "$MODE" = "1" ];then
    read -p "代理目标: " PROXY
    echo "    location / {
        proxy_pass http://$PROXY;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}" >> /etc/nginx/conf.d/$DOMAIN.conf
else
    echo "    root $WEB_ROOT;
    index index.html;
}" >> /etc/nginx/conf.d/$DOMAIN.conf
    echo "$DOMAIN 正常" > $WEB_ROOT/index.html
fi

# 重启
nginx -t && systemctl restart nginx
echo "完成: https://$DOMAIN"
