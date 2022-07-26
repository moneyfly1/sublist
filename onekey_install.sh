#!/bin/bash
 
blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

#判断系统
check_os(){
    if [ ! -e '/etc/redhat-release' ]; then
        red "==============="
        red " 仅支持CentOS7"
        red "==============="
        exit
    fi
    if  [ -n "$(grep ' 6\.' /etc/redhat-release)" ] ;then
        red "==============="
        red " 仅支持CentOS7"
        red "==============="
        exit
    fi
    if  [ -n "$(grep ' 8\.' /etc/redhat-release)" ] ;then
        red "==============="
        red " 仅支持CentOS7"
        red "==============="
        exit
    fi
}

disable_selinux(){

    yum -y install net-tools socat
    Port80=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 80`
    Port443=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 443`
    if [ -n "$Port80" ]; then
        process80=`netstat -tlpn | awk -F '[: ]+' '$5=="80"{print $9}'`
        red "==========================================================="
        red "检测到80端口被占用，占用进程为：${process80}，本次安装结束"
        red "==========================================================="
        exit 1
    fi
    if [ -n "$Port443" ]; then
        process443=`netstat -tlpn | awk -F '[: ]+' '$5=="443"{print $9}'`
        red "============================================================="
        red "检测到443端口被占用，占用进程为：${process443}，本次安装结束"
        red "============================================================="
        exit 1
    fi
    if [ -f "/etc/selinux/config" ]; then
        CHECK=$(grep SELINUX= /etc/selinux/config | grep -v "#")
        if [ "$CHECK" == "SELINUX=enforcing" ]; then
            green "$(date +"%Y-%m-%d %H:%M:%S") - SELinux状态非disabled,关闭SELinux."
            setenforce 0
            sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
            #loggreen "SELinux is not disabled, add port 80/443 to SELinux rules."
            #loggreen "==== Install semanage"
            #logcmd "yum install -y policycoreutils-python"
            #semanage port -a -t http_port_t -p tcp 80
            #semanage port -a -t http_port_t -p tcp 443
            #semanage port -a -t http_port_t -p tcp 37212
            #semanage port -a -t http_port_t -p tcp 37213
        elif [ "$CHECK" == "SELINUX=permissive" ]; then
            green "$(date +"%Y-%m-%d %H:%M:%S") - SELinux状态非disabled,关闭SELinux."
            setenforce 0
            sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
        fi
    fi
    firewall_status=`systemctl status firewalld | grep "Active: active"`
    if [ -n "$firewall_status" ]; then
        green "检测到firewalld开启状态，关闭firewalld"
        #firewall-cmd --zone=public --add-port=80/tcp --permanent
        #firewall-cmd --zone=public --add-port=443/tcp --permanent
        #firewall-cmd --reload
        systemctl stop firewalld
        systemctl disable firewalld
    fi
    yum install -y iptables-services
    systemctl start iptables
    systemctl enable iptables
    iptables -F
    SSH_PORT=$(awk '$1=="Port" {print $2}' /etc/ssh/sshd_config)
    if [ ! -n "$SSH_PORT" ]; then
        iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
    else
        iptables -A INPUT -p tcp -m tcp --dport ${SSH_PORT} -j ACCEPT
    fi
    iptables -A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
    iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    service iptables save
    green "====================================================================="
    green "安全起见，iptables仅开启ssh,http,https端口，如需开放其他端口请自行放行"
    green "====================================================================="
}

check_domain(){
    green "========================="
    yellow "请输入绑定到本VPS的域名"
    yellow "   安装时请关闭CDN"
    green "========================="
    read your_domain
    real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    local_addr=`curl ipv4.icanhazip.com`
    if [ $real_addr == $local_addr ] ; then
        green "============================="
        green "域名解析正常，开始安装爬虫"
        green "============================="
        sleep 1s
        download_pc   
        install_nginx
        config_ssl
    else
        red "================================="
        red "域名解析地址与本VPS IP地址不一致"
        red "本次安装失败，请确保域名解析正常"
        red "================================="
        exit 1
    fi
}


install_nginx(){
    echo
    echo
    green "==============="
    green "  2.安装nginx"
    green "==============="
    sleep 1
    #rpm -Uvh http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm --force --nodeps
    while [ ! -f "nginx-release-centos-7-0.el7.ngx.noarch.rpm" ]
    do
        wget http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm
        if [ ! -f "nginx-release-centos-7-0.el7.ngx.noarch.rpm" ]; then
            logred "$(date +"%Y-%m-%d %H:%M:%S") - 下载nginx rpm包失败，继续重试..."
        fi
    done
    rpm -Uvh nginx-release-centos-7-0.el7.ngx.noarch.rpm --force --nodeps
    yum install -y nginx
    systemctl enable nginx.service
    systemctl stop nginx.service
    rm -f /etc/nginx/conf.d/default.conf
    rm -f /etc/nginx/nginx.conf
    mkdir /etc/nginx/ssl
    if [ `yum list installed | grep nginx | wc -l` -ne 0 ]; then
        echo
        green "【checked】 nginx安装成功"
        echo
        echo
        sleep 1
    fi

cat > /etc/nginx/nginx.conf <<-EOF
user  nginx;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    error_log /var/log/nginx/error.log error;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    include /etc/nginx/conf.d/*.conf;
}
EOF

    curl https://get.acme.sh | sh -s email=my@example.com
    ~/.acme.sh/acme.sh  --issue  -d $your_domain  --standalone
    ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
        --key-file   /etc/nginx/ssl/$your_domain.key \
        --fullchain-file /etc/nginx/ssl/fullchain.cer

cat > /etc/nginx/conf.d/default.conf<<-EOF
server {
    listen 80 default_server;
    server_name _;
    return 404;  
}
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/nginx/ssl/fullchain.cer; 
    ssl_certificate_key /etc/nginx/ssl/$your_domain.key;
    return 404;
}
server { 
    listen       80;
    server_name  $your_domain;
    rewrite ^(.*)$  https://\$host\$1 permanent; 
}
server {
    listen 443 ssl http2;
    server_name $your_domain;
    root /usr/share/nginx/html;
    index index.php index.html;
    ssl_certificate /etc/nginx/ssl/fullchain.cer; 
    ssl_certificate_key /etc/nginx/ssl/$your_domain.key;
    ssl_stapling on;
    ssl_stapling_verify on;
    add_header Strict-Transport-Security "max-age=31536000";
    access_log /var/log/nginx/hostscube.log combined;
    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    location / {
       proxy_pass http://127.0.0.1:12580/;
    }
}
EOF

}


config_ssl(){

    echo
    green "===================="
    green " 3.验证ssl证书"
    green "===================="
    echo
    echo
    sleep 1
    systemctl restart nginx.service
    ~/.acme.sh/acme.sh  --issue --force  -d $your_domain  --nginx
    ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
        --key-file   /etc/nginx/ssl/$your_domain.key \
        --fullchain-file /etc/nginx/ssl/fullchain.cer \
        --reloadcmd  "systemctl restart nginx"	
    sleep 1
    echo
    green "===================="
    green " 爬虫安装成功"
    green "===================="
    echo
  
}


download_pc(){
    echo
    green "==============="
    green "  1.安装爬虫"
    green "==============="
    sleep 1
    wget https://gh.ddlc.top/https://github.com/lanhebe/proxypool/releases/download/v0.6/proxypool-linux-amd64-v0.6.0.gz
    gzip -d proxypool-linux-amd64-v0.6.0.gz
    mv proxypool-linux-amd64-v0.6.0 proxypool
    chmod 755 proxypool

    wget https://raw.iqiq.io/lanhebe/proxypool/master/config.yaml
    wget https://raw.iqiq.io/lanhebe/proxypool/master/source.yaml
   
    cat > ./config.yaml <<-EOF
    domain: $your_domain
    port:                 # default 12580
    # source list file
    source-files:
      # use local file
      - ./source.yaml
      # use web file
      # - https://example.com/config/source.yaml
    # ======= 可选项，留空使用default值  =======
    # postgresql database info
    database_url: ""
    # interval between each crawling
    crawl-interval:       # v0.5.x default 60 (minutes)
    crontime:             # v0.4.x default 60 (minutes). Deprecated in the newest version
    # speed test
    speedtest: false      # default false. Warning: this will consume large network resources.
    speedtest-interval:   # default 720 (min)
    connection:           # default 5. The number of speed test connections simultaneously
    timeout:              # default 10 (seconds).
    ## active proxy speed test
    active-interval:      # default 60 (min)
    active-frequency:     # default 100 (requests per interval)
    active-max-number:    # default 100. If more than this number of active proxies, the extra will be deprecated by speed
    # cloudflare api
    cf_email: ""
    cf_key: ""
EOF
   
    nohup ./proxypool -c config.yaml >/dev/null 2>/dev/null &
    
}



uninstall_pc(){
    red "============================================="
    red "你的pc数据将全部丢失！！你确定要卸载吗？"
    read -s -n1 -p "按回车键开始卸载，按ctrl+c取消"
    yum remove -y nginx
    pkill proxypool
    rm -rf ~/proxypool
    rm -rf ~/config.yaml
    rm -rf ~/source.yaml
    green "=========="
    green " 卸载完成"
    green "=========="
}

start_menu(){
    clear
    green "======================================="
    green " 环境：适用于CentOS7，一键安装免费节点爬虫"
    green " 作者：Littleyu+部分代码来源网络"
    green " 网站：yugogo.xyz"
    green " Youtube频道：yu little"
    green "======================================="
    green "1. 一键安装免费节点爬虫"
    red "2. 卸载爬虫"
    yellow "0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    check_os
    disable_selinux
    check_domain
    ;;
    2)
    uninstall_pc
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    echo "请输入正确数字"
    sleep 2s
    start_menu
    ;;
    esac
}

start_menu
