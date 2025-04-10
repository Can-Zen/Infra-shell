#!/usr/bin/env bash
############################## usage #######################################
# tag="xx cluster"
# script_path="$(dirname ${BASH_SOURCE[0]})"
# source "$script_path/../00_utils/_ssh_passfree.sh"
# _ssh_passfree "$tag"
#
# function get_ip2host() {
#     declare -A ip2host
#     # get ips and hosts save to ${!ip2host[@]}
#     awk -v tag="$tag" '
#         /# '"$tag"' ssh passfree start/ {start=1; next}
#         /# '"$tag"' ssh passfree end/ {start=0; next}
#         start && !/^#/ && NF > 1 {ip2host[$1]=$2}
#         END { for (ip in ip2host) { print ip " -> " ip2host[ip]; } }
#     ' /etc/hosts
# }
# get_ip2host
############################## usage #######################################

script_path="$(dirname ${BASH_SOURCE[0]})"
# import some define
source "$script_path/_print.sh"
source "$script_path/_logger.sh"

function _ssh_passfree_config() {
    _print_line title "Plan $tag nodes ip and hostname, configure ssh passwordfree"

    _logger info "Obtain the list of IP addresses and hostnames from user input"
    echo -e "${green}Enter IPs and hostnames, one per line, an empty line completes the input, example:"
    echo -e "${gray}192.168.85.121 server-01\n192.168.85.122 server-02\n192.168.85.123 server-03\n${reset}"

    while true; do
        read -p "" line
        [[ -z $line ]] && break
        ip=$(echo "$line" | awk '{print $1}')
        hostname=$(echo "$line" | awk '{print $2}')
        ip2host["$ip"]="$hostname"
    done
    read -rp "Confirm info? (y/n) [Enter for y]: " answer
    answer=${answer:-"y"}
    [[ "$answer" =~ ^[Yy]$ ]] || { _logger error "User cancelled, exiting..." && exit 1; }

    _logger info "Start configuring password-free SSH login"
    while true; do
        printf "Ensure all servers have ${red}the same password ${reset}and enter it: "
        read -rsp "" srv_passwd
        echo
        read -rsp "Re-enter password to confirm: " confirm_srv_passwd
        _print_line split blank 2
        [[ "${srv_passwd}" == "${confirm_srv_passwd}" ]] && break || \
            _logger warn "Password don't match, please re-enter."
    done

    which sshpass || dnf install -y sshpass
    # Generate a ssh key pair
    for ip in "${!ip2host[@]}"; do
        sshpass -p "$srv_passwd" ssh -q -o StrictHostKeyChecking=no -o LogLevel=QUIET "$ip" <<-EOF
mkdir -p ${HOME}/.ssh
[[ -f ${private_key_file} ]] || ssh-keygen -t ed25519 -b 4096 -N '' -f ${private_key_file} -q
EOF
    # Collect the public key from current node
    ssh_keys[$ip]=$(sshpass -p "$srv_passwd" ssh -q -o StrictHostKeyChecking=no -o LogLevel=QUIET "$ip" "cat ${public_key_file}")
    done

    # Add authorized_key and known_hosts
    for ip in "${!ip2host[@]}"; do
        declare -p ip2host ssh_keys > /tmp/cmd
        cat >> /tmp/cmd <<-EOF
echo "# $tag ssh passfree start" >> /etc/hosts
for tip in "\${!ip2host[@]}"; do
    # authorized_keys
    touch ${auth_key_file}
    echo \${ssh_keys[\$tip]} $tag >> ${auth_key_file}
    chmod 600 ${auth_key_file}

    # update hosts
    echo "\$tip \${ip2host[\$tip]}" >> /etc/hosts

    # known_hosts
    touch ${known_hosts_file}
    sed -i "/^\$tip/d" ${known_hosts_file}
    ssh-keyscan -t ed25519 \$tip 2>/dev/null | sed "s/$/ $tag/" >> ${known_hosts_file}
    ssh-keyscan -t ed25519 \${ip2host[\$tip]} 2>/dev/null | sed "s/$/ $tag/" >> ${known_hosts_file}
done
echo "# $tag ssh passfree end" >> /etc/hosts

rm -- "\$0"
EOF
        sshpass -p "$srv_passwd" scp -o StrictHostKeyChecking=no "/tmp/cmd" "$USER@$ip:/tmp/"
        sshpass -p "$srv_passwd" ssh -q -o StrictHostKeyChecking=no -o LogLevel=QUIET "$ip" "bash /tmp/cmd"
        ssh -o BatchMode=yes -o ConnectTimeout=5 "$USER@$ip" "echo 'SSH login successful for ${ip2host[$ip]} ($ip)'" 
    done

    _print_line split -
    _logger info "SSH passwordless login is configured successfully!\n"
}

function _ssh_passfree_undo() {
    # clear ssh passfree
    sed -i "/$tag/d" ${auth_key_file} ${known_hosts_file}
    # clear hosts
    sed -i "/# $tag ssh passfree start/,/# $tag ssh passfree end/d" /etc/hosts

    _print_line split -
    _logger info "SSH passwordless login has been successfully undone!\n"
}

function _ssh_passfree() {
    local tag=$2
    local -A ip2host ssh_keys
    local private_key_file="${HOME}/.ssh/id_ed25519"
    local public_key_file="${HOME}/.ssh/id_ed25519.pub"
    local auth_key_file="${HOME}/.ssh/authorized_keys"
    local known_hosts_file="${HOME}/.ssh/known_hosts"

    case $1 in
        config)
            shift
            _ssh_passfree_config
            ;;
        undo)
            shift
            _ssh_passfree_undo
            ;;
        *)
            printf "Invalid option $*\n"
            printf "${green}Usage: ${reset}\n"
            printf "    ${green}$FUNCNAME config${gray}/undo xx-cluster${reset}\n"
            exit 1
            ;;
    esac
}