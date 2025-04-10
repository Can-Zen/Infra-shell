#!/bin/bash
set -o errexit

script_path="$(dirname ${BASH_SOURCE[0]})"
# import some define
source "$script_path/../00_utils/_print.sh"
source "$script_path/../00_utils/_logger.sh"

CHRONY_CONF="/etc/chrony.conf"

_print_line title "Install and update chrony service"

_logger info "Check and install chrony"
which chronyc || dnf install -y chronyd
_print_line split -
ls -ld /usr/bin/chronyc /usr/sbin/chronyd /etc/chrony.conf
_print_line split -

_logger info "Backup and update chrony config"
[[ -f $CHRONY_CONF ]] && cp -v $CHRONY_CONF ${CHRONY_CONF}_$(date +'%Y%m%d-%H%M').bak
tee $CHRONY_CONF <<-EOF
server ntp.aliyun.com iburst
server cn.pool.ntp.org iburst
server ntp.ntsc.ac.cn iburst
local stratum 10
makestep 1.0 3
rtcsync
driftfile /var/lib/chrony/drift
logdir /var/log/chrony
EOF

_logger info "Start/Restart chrony service"
systemctl restart chrony && systemctl enable $_ && systemctl status --no-pager $_

_logger info "Verifying the time source and synchronization status"
chronyc sources -v

_print_line split -
_logger info "Chrony service deployed successfully!"