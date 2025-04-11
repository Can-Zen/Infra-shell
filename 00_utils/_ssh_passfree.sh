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

    _logger info "1. Get the list of IP addresses and hostnames from user input"
    echo -e "${green}Enter IPs and hostnames, one per line, an empty line completes the input, example:"
    echo -e "${gray}192.168.85.121 server-01\n192.168.85.122 server-02\n192.168.85.123 server-03${reset}"

    while true; do
        read -p "" line
        [[ -z $line ]] && break
        ip=$(echo "$line" | awk '{print $1}')
        hostname=$(echo "$line" | awk '{print $2}')
        ip2host["$ip"]="$hostname"
    done
    read -rp "Confirm info and continue? (y/n) [Enter for y]: " answer
    answer=${answer:-"y"}
    [[ "$answer" =~ ^[Yy]$ ]] || { _logger error "User cancelled, exiting..." && exit 1; }

    _print_line split blank 2
    _logger info "2. Get and identify the host for one-way password-free login"
    declare -a matched_one_way_hosts
    while true; do
        echo -e "${green}Please enter the hostname of the host that only allows one-way password-free login to other hosts,"
        printf "${green}(e.g., ${red}master/controller${green}) [Enter for none]: ${reset}"
        read -p "" one_way_host_str
        echo
        if [[ -n "$one_way_host_str" ]]; then
            matched_one_way_ips=()
            found=false

            for ip in "${!ip2host[@]}"; do
                hostname=${ip2host[$ip]}
                if [[ $hostname =~ ^$one_way_host_str ]]; then
                    matched_one_way_ips+=("$ip")
                    found=true
                fi
            done

            if [[ "$found" = true ]]; then
                for ip in "${matched_one_way_ips[@]}"; do
                    echo -e "$ip ${red}${ip2host[$ip]}${reset}"
                done
                echo -e "Matched the above machines."
                break
            else
                _logger warn "No match found for host pattern: $one_way_host_str"
            fi
        else
            matched_one_way_ips=("${!ip2host[@]}")
            echo -e "No matching required this time."
            break
        fi
    done

    read -rp "Confirm info and continue? (y/n) [Enter for y]: " answer
    answer=${answer:-"y"}
    [[ "$answer" =~ ^[Yy]$ ]] || { _logger error "User cancelled, exiting..." && exit 1; }
    
    which sshpass >/dev/null || dnf install -y sshpass

    _print_line split blank 2
    while true; do
        printf "Ensure all servers have ${red}the same password ${reset}and enter it: "
        read -rsp "" srv_passwd
        echo

        conn_status=1
        for ip in "${!ip2host[@]}"; do
            if sshpass -p "$srv_passwd" ssh -q -o StrictHostKeyChecking=no -o LogLevel=QUIET "$ip" true; then
                echo -e "${green}SSH connection to $ip succeeded using password.${reset}"
            else
                echo -e "${red}SSH connection to $ip failed using password. Please re-enter.${reset}"
                conn_status=0
                break
            fi
        done

        if [[ $conn_status -eq 1 ]]; then
            break
        fi
    done

    _print_line split blank 2
    _logger info "3. Start configuring password-free SSH login"

    # Generate a ssh key pair
    _logger info "3.1 Start generate a ssh key pair"
    for ip in "${!ip2host[@]}"; do
        sshpass -p "$srv_passwd" ssh -q -o StrictHostKeyChecking=no -o LogLevel=QUIET "$ip" <<-EOF
mkdir -p ${HOME}/.ssh
[[ -f ${private_key_file} ]] || ssh-keygen -t ed25519 -b 4096 -N '' -f ${private_key_file} -q
EOF
    # Collect the public key from current node
    ssh_keys[$ip]=$(sshpass -p "$srv_passwd" ssh -q -o StrictHostKeyChecking=no -o LogLevel=QUIET "$ip" "cat ${public_key_file}")
    done

    # Add hosts and authorized_key
    _logger info "3.2 Start add hosts and authorized_key"
    for ip in "${!ip2host[@]}"; do
        declare -p ip2host matched_one_way_ips ssh_keys > /tmp/cmd
        cat >> /tmp/cmd <<-EOF
echo "# $tag ssh passfree start" >> /etc/hosts
for hip in "\${!ip2host[@]}"; do
    # update hosts
    echo "\$hip \${ip2host[\$hip]}" >> /etc/hosts
done

for aip in "\${matched_one_way_ips[@]}"; do
    # authorized_keys
    touch ${auth_key_file}
    echo \${ssh_keys[\$aip]} "#$tag" >> ${auth_key_file}
    chmod 600 ${auth_key_file}
done
echo "# $tag ssh passfree end" >> /etc/hosts

rm -- "\$0"
EOF
        sshpass -p "$srv_passwd" scp -o StrictHostKeyChecking=no "/tmp/cmd" "$USER@$ip:/tmp/"
        sshpass -p "$srv_passwd" ssh -q -o StrictHostKeyChecking=no -o LogLevel=QUIET "$ip" "bash /tmp/cmd"
    done

    # Add known_hosts
    _logger info "3.3 Start add known_hosts"
    for ip in "${matched_one_way_ips[@]}"; do
        declare -p ip2host > /tmp/fcmd
        cat >> /tmp/fcmd <<-EOF
for kip in "\${!ip2host[@]}"; do
    touch ${known_hosts_file}
    sed -i "/^\$kip/d" ${known_hosts_file}
    ssh-keyscan -t ed25519 \$kip 2>/dev/null | sed "s/$/ #$tag/" >> ${known_hosts_file}
    ssh-keyscan -t ed25519 \${ip2host[\$kip]} 2>/dev/null | sed "s/$/ #$tag/" >> ${known_hosts_file}
done

rm -- "\$0"
EOF
        sshpass -p "$srv_passwd" scp -o StrictHostKeyChecking=no "/tmp/fcmd" "$USER@$ip:/tmp/"
        sshpass -p "$srv_passwd" ssh -q -o StrictHostKeyChecking=no -o LogLevel=QUIET "$ip" "bash /tmp/fcmd"
    done

    # verify ssh passwordless
    _logger info "3.4 Start verify ssh passwordless ..."
    conn_status=1
    for ip in "${!ip2host[@]}"; do
        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$USER@$ip" true; then
            echo -e "${green}SSH passwordless login verification succeeded for ${ip2host[$ip]} ($ip).${reset}"
        else
            echo -e "${red}SSH passwordless login verification failed for ${ip2host[$ip]} ($ip).${reset}"
            conn_status=0
            break
        fi
    done
    [[ $conn_status -eq 1 ]] ||  exit 1

    _print_line split blank 2
    # update hostname
    _logger info "4. Start update hostname on the remote host"
    read -p "Need to synchronously update the remote host's hostname to the planned one? (y/n) [Enter for y]: " answer
    answer=${answer:-"y"}
    [[ "$answer" =~ ^[Yy]$ ]] || { _logger error "User cancelled, exiting..." && exit 1; }
    for ip in "${!ip2host[@]}"; do
        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$USER@$ip" "hostnamectl set-hostname ${ip2host[$ip]}"; then
            echo -e "${green}Hostname updated successfully on ${ip2host[$ip]} ($ip).${reset}"
        else
            echo -e "${red}Failed to update hostname on ${ip2host[$ip]} ($ip).${reset}"
        fi
    done

    _print_line split -
    _logger info "SSH passwordless login configuration succeeded!\n"
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
    local auth_key_file="${HOME}/.ssh/authorized_keys"   # About who can connect to me
    local known_hosts_file="${HOME}/.ssh/known_hosts"    # About who I have connected to

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