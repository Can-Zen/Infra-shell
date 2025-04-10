sed -i "/SELINUX=/s/enforcing/disabled/g" /etc/selinux/config  # Disable SELinux in config
setenforce 0   # Set SELinux to permissive
sestatus       # Check SELinux status