#!/bin/bash
set -o errexit

script_path="$(dirname ${BASH_SOURCE[0]})"
# import some define
source "$script_path/../00_utils/_print.sh"
source "$script_path/../00_utils/_trap.sh"
source "$script_path/../00_utils/_logger.sh"

# capture errors and print environment variables
trap '_trap_print_env \
    SRV_IP NGX_VER NGX_HOME NGX_CONF NGX_LISTEN_PORT NGX_COMPILE_OPTS \
    NGX_ACCESS_URL WEB_ROOT_PATH WEB_DOMAINS
' ERR

# define golabal variables
SRV_IP="$(ip -4 addr show | grep inet | grep -v 127.0.0.1 | awk 'NR==1 {print $2}' | cut -d'/' -f1)"

function _help() {
    printf "Invalid option $*\n"
    printf "${green}Usage: ${reset}\n"
    printf "    ${gray}bash ${blue}$0 ${green}install 1.25.1 ${gray}/usr/local/nginx 80 ${reset}\n"
    printf "    ${gray}bash ${blue}$0 ${green}add_vhost www.domain01.com ${gray}www.domain02.com ... ${reset}\n"
    printf "    ${gray}bash ${blue}$0 ${green}remove_vhost www.domain01.com ${gray}www.domain02.com ... ${reset}\n"
    printf "    ${gray}bash ${blue}$0 ${green}upgrade 1.26.2 ${gray}/usr/local/nginx ${reset}\n"
    printf "    ${gray}bash ${blue}$0 ${green}remove ${gray}/usr/local/nginx ${reset}\n"
}


function install() {
    local NGX_VER="$1"
    local NGX_PKG_PREFIX="nginx-$NGX_VER"
    local NGX_URL="http://nginx.org/download/$NGX_PKG_PREFIX.tar.gz"
    local NGX_HOME="${2:-/usr/local/nginx}"
    local NGX_LISTEN_PORT="${3:-80}"
    local NGX_CONF="$NGX_HOME/conf/nginx.conf"
    local NGX_ACCESS_URL="http://${SRV_IP}:${NGX_LISTEN_PORT}/"
    local NGX_COMPILE_OPTS=" \
        --prefix=$NGX_HOME \
        --with-http_stub_status_module \
        --with-http_ssl_module \
        --with-http_v2_module \
        "

    # check args
    local RELEASE_VERS=$(curl -s "https://api.github.com/repos/nginx/nginx/tags?per_page=100" | \
        jq -r '.[].name' | grep -E '^release-[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/release-//g')
    if [[ -z "$NGX_VER" ]] || ! echo ${RELEASE_VERS[@]} | grep -wq "$NGX_VER"; then
        _logger error "Version mismatch. Please use the official version below:"
        echo ${RELEASE_VERS[@]}
        exit 1
    fi
    [[ -z "$(ls -A $NGX_HOME 2>/dev/null)" ]] || { _logger error "Nginx is already installed in $NGX_HOME." && exit 1; }

    _print_line title "Install nginx service"

    _logger info "1. Install necessary dependencies"
    dnf install -y tar wget gcc make pcre-devel zlib-devel openssl-devel

    _logger info "2. Download and extract the nginx source code"
    if [[ -f /usr/local/src/$NGX_PKG_PREFIX.tar.gz ]]; then
        _logger warn "$NGX_PKG_PREFIX.tar.gz is already exists in /usr/local/src/, will extract and use ..."
    else
        wget -c $NGX_URL -P /usr/local/src/
    fi
    cd /usr/local/src/
    tar -zxf $NGX_PKG_PREFIX.tar.gz

    _logger info "3. Configure, make, make install"
    cd $NGX_PKG_PREFIX
    ./configure $NGX_COMPILE_OPTS
    local make_threads=$(( (t=($((nproc))*3/2+1)/2*2, t>0 ? t : 1) ))
    time make -j${make_threads} | tee -a make.log
    _logger info "nginx make completed."
    time make install -j${make_threads}  | tee -a make_install.log
    _logger info "nginx make install completed."
    cd .. && rm -rf $NGX_PKG_PREFIX

    _logger info "4. Update the nginx config"
    cp -v $NGX_CONF ${NGX_CONF}_$(date +'%Y%m%d-%H%M').bak
    sed -i "/listen /s/80/$NGX_LISTEN_PORT/g" $NGX_CONF && grep "listen" $_
    echo

    _logger info "5. Starting the nginx service"
    useradd -r nginx
    chown -R nginx:nginx $NGX_HOME
    # Use absolute path to start NGINX due to config file issues with PATH environment variable
    $NGX_HOME/sbin/nginx
    ps -ef | grep "[n]ginx" || _logger error "Nginx start failed. Please manual start."

    _logger info "6. Open the corresponding firewall ports"
    if systemctl status firewalld >/dev/null; then
        firewall-cmd --add-port=$NGX_LISTEN_PORT/tcp --permanent &>/dev/null
        firewall-cmd --reload >/dev/null
        echo -e "Current open ports in the firewall: $(firewall-cmd --list-ports)"
    else
        _logger warn "System firewalld is currently disabled."
    fi

    _logger info "7. Verifying nginx service via access url ..."
    curl -sv $NGX_ACCESS_URL

    _print_line split -
    _logger info "nginx service has been successfully installed. Summary:"
    echo -e "${green}nginx home: $NGX_HOME;\nnginx config: $NGX_CONF"
    echo -e "${green}nginx version details:${reset}"
    $NGX_HOME/sbin/nginx -V
    echo
    echo -e "${green}nginx process details:${reset}"
    ps -ef | grep "[n]ginx" | grep -v "pts"
    echo
    echo -e "${green}nginx access url: $NGX_ACCESS_URL${reset}\n"
}


function add_vhost() {
    local NGX_HOME="/usr/local/nginx"
    local NGX_CONF="$NGX_HOME/conf/nginx.conf"
    local NGX_LISTEN_PORT="$(ss -tunlp | grep nginx | awk '{print $5}' | cut -d':' -f2)"
    local WEB_ROOT_PATH="$1"
    local WEB_DOMAINS="${@:2}"

    [[ -z "$(ls -A $NGX_HOME 2>/dev/null)" ]] && { _logger error "Nginx is not installed." && exit 1; }

    _print_line title "Pluggable addition of virtual host configuration for Nginx"

    _logger info "1. Backup current config"
    cp -v $NGX_CONF ${NGX_CONF}_$(date +'%Y%m%d-%H%M').bak

    _logger info "2. Update config according to user requirements"
    mkdir -p $NGX_HOME/sites-available $NGX_HOME/sites-enabled
    local include_line="        include $NGX_HOME/sites-enabled/*;"
    if ! grep -qF -- "${include_line}" "$NGX_CONF"; then
        sed -i ':a;N;$!ba;s/}\r*$//' "$NGX_CONF"
        sed -i "$ a\\${include_line}\n}" "$NGX_CONF"
        _logger info "Added include line to Nginx config."
    else
        _logger warn "Include line already exists in Nginx config, no changes made."
    fi

    for domain in $WEB_DOMAINS; do
        _logger info "Start processes vhost $domain"
        _print_line split -

        mkdir -p $WEB_ROOT_PATH/$domain && \cp -rf $NGX_HOME/html/* $_
        sed -i "/^<h1>/s/nginx/<span style=\"color: red;\">$domain/g" $WEB_ROOT_PATH/$domain/index.html
        cat > $NGX_HOME/sites-available/$domain <<-EOF
server {
        listen       $NGX_LISTEN_PORT;
        server_name  $domain;
        location / {
            root   $WEB_ROOT_PATH/$domain;
            index  index.html index.htm;
            charset utf-8;
        }
}
EOF
        ln -sf $NGX_HOME/sites-available/$domain $NGX_HOME/sites-enabled/
        _logger info "Test and reload config"
        $NGX_HOME/sbin/nginx -t
        $NGX_HOME/sbin/nginx -s reload && sleep 3

        _logger info "Verifying access: $domain"
        echo "$SRV_IP $domain" >> /etc/hosts
        curl --silent --head --max-time 3 http://$domain:$NGX_LISTEN_PORT/
        _logger info "$domain vhost add success! Summary:"
        echo -e "${green}    access address: http://$domain:$NGX_LISTEN_PORT/"
        echo -e "${green}    config path: $NGX_HOME/sites-enabled/$domain"
        echo -e "${green}    website resource path: $WEB_ROOT_PATH/$domain${reset}"
    done
}


function remove_vhost() {
    local NGX_HOME="/usr/local/nginx"
    local NGX_LISTEN_PORT="$(ss -tunlp | grep nginx | awk '{print $5}' | cut -d':' -f2)"
    local WEB_ROOT_PATH="$1"
    local WEB_DOMAINS="${@:2}"

    [[ -z "$(ls -A $NGX_HOME 2>/dev/null)" ]] && { _logger error "Nginx is not installed." && exit 1; }

    _print_line title "Pluggable removal of virtual host configuration for Nginx"

    for domain in $WEB_DOMAINS; do
        _logger info "Start processes vhost $domain"
        _print_line split -
        [[ -f $NGX_HOME/sites-enabled/$domain ]] || { _logger error "$domain vhost does not exist" && continue; }
        rm -rf $NGX_HOME/sites-enabled/$domain
        $NGX_HOME/sbin/nginx -t
        $NGX_HOME/sbin/nginx -s reload && sleep 3

        _logger info "$domain vhost remove success! But some resource are still preserved:"
        echo -e "${gray}    access address: http://$domain:$NGX_LISTEN_PORT/"
        echo -e "${yellow}    config path: $NGX_HOME/sites-enabled/$domain"
        echo -e "${yellow}    website resource path: $WEB_ROOT_PATH/$domain${reset}"

        sed -i "/$SRV_IP $domain/d" /etc/hosts
    done
}


function upgrade() {
    local NGX_VER="$1"
    local NGX_PKG_PREFIX="nginx-$NGX_VER"
    local NGX_URL="http://nginx.org/download/$NGX_PKG_PREFIX.tar.gz"
    local NGX_HOME="${2:-/usr/local/nginx}"
    local NGX_OLD_VER="$($NGX_HOME/sbin/nginx -v 2>&1 | cut -d'/' -f2)"
    local NGX_LISTEN_PORT="$(ss -tunlp | grep nginx | awk '{print $5}' | cut -d':' -f2)"
    local NGX_ACCESS_URL="http://${SRV_IP}:${NGX_LISTEN_PORT}/"
    local NGX_COMPILE_OPTS=" \
    --prefix=$NGX_HOME \
    --with-http_stub_status_module \
    --with-http_ssl_module \
    --with-http_v2_module \
    "

    [[ -z "$(ls -A $NGX_HOME 2>/dev/null)" ]] && { _logger error "Nginx is not installed." && exit 1; }

    _print_line title "Upgrade nginx version"

    _logger info "1. Install necessary dependencies"
    dnf install -y tar wget gcc make pcre-devel zlib-devel openssl-devel

    _logger info "2. Download and extract the nginx source code"
        if [[ -f /usr/local/src/$NGX_PKG_PREFIX.tar.gz ]]; then
        _logger warn "$NGX_PKG_PREFIX.tar.gz is already exists in /usr/local/src/, will use."
    else
        wget -c $NGX_URL -P /usr/local/src/
    fi
    cd /usr/local/src/
    _logger info "Decompressing ..."
    tar -zxf $NGX_PKG_PREFIX.tar.gz

    _logger info "3. Configure, make, make install"
    cd $NGX_PKG_PREFIX
    ./configure $NGX_COMPILE_OPTS
    local make_threads=$(( (t=($((nproc))*3/2+1)/2*2, t>0 ? t : 1) ))
    time make -j${make_threads} | tee -a make.log
    _logger info "nginx make completed."
    time make install -j${make_threads}  | tee -a make_install.log
    _logger info "nginx make install completed."

    _logger info "4. Backup and overwrite the old binary"
    mv $NGX_HOME/sbin/nginx $NGX_HOME/sbin/nginx_$NGX_OLD_VER
    cp -v objs/nginx $NGX_HOME/sbin/
    cd .. && rm -rf $NGX_PKG_PREFIX

    _logger info "5. Performing smooth upgrade of Nginx ..."
    $NGX_HOME/sbin/nginx -t
    kill -USR2 $(pgrep -f "nginx: master")
    if (( $(ps -ef | grep "[n]ginx: master" | wc -l) == 2 )); then
        kill -WINCH $(cat /usr/local/nginx/logs/nginx.pid.oldbin)
    else
        _print_line_msg "RED" "nginx upgrade failure."
        exit 1
    fi

    _logger info "6. Verifying nginx service via access url ..."
    curl -sv $NGX_ACCESS_URL

    _print_line split -
    _logger info "nginx service has been successfully upgraded. Summary:"
    echo -e "${green}nginx home: $NGX_HOME;\nnginx config: $NGX_CONF"
    echo -e "${green}nginx old version is $NGX_OLD_VER, and new version details:${reset}"
    $NGX_HOME/sbin/nginx -V
    echo
    echo -e "${green}nginx process details:${reset}"
    ps -ef | grep "[n]ginx" | grep -v "pts"
    echo
    echo -e "${green}nginx access url: $NGX_ACCESS_URL${reset}\n"
}

function remove() {
    local NGX_HOME="${1:-/usr/local/nginx}"
    local NGX_LISTEN_PORT="$(ss -tunlp | grep nginx | awk '{print $5}' | cut -d':' -f2)"

    [[ -z "$(ls -A $NGX_HOME 2>/dev/null)" ]] && { _logger error "Nginx is not installed." && exit 1; }

    _print_line title "Remove nginx service"

    _logger info "1. Kill nginx processes ..."
    for i in $(seq 1 10); do
        ps -ef | grep "[n]ginx" | grep -v "pts" && pkill -QUIT mysql && sleep 3 || break
    done

    _logger info "2. Delete related files ..."
    rm -rfv $NGX_HOME

    _logger info "3. Delete nginx user"
    id nginx && userdel -f nginx

    _logger info "4. Close the corresponding firewall ports"
    if systemctl status firewalld >/dev/null; then
        firewall-cmd --remove-port=$NGX_LISTEN_PORT/tcp --permanent &>/dev/null
        firewall-cmd --reload >/dev/null
        echo -e "Current open ports in the firewall: $(firewall-cmd --list-ports)"
    else
        _logger warn "System firewalld is currently disabled."
    fi

    _logger info "5. Remove the corresponding environment variable"
    sed -i "/NGX_HOME/d" /etc/profile

    _print_line split -
    _logger info "Nginx has been successfully removed.\n"

}


case $1 in
    install)
        shift
        [[ $# -gt 0 ]] || { _help && exit 1; }
        install $*
        ;;
    add_vhost)
        shift
        [[ $# -gt 0 ]] || { _help && exit 1; }
        add_vhost "/var/www/shared-resources" ${@:1}
        ;;
    remove_vhost)
        shift
        [[ $# -gt 0 ]] || { _help && exit 1; }
        remove_vhost "/var/www/shared-resources" ${@:1}
        ;;
    upgrade)
        shift
        [[ $# -gt 0 ]] || { _help && exit 1; }
        upgrade $*
        ;;
    remove)
        shift
        remove $*
        ;;
    *)
        _help && exit 1
        ;;
esac