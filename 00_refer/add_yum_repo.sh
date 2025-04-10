##################################### Rocky Linux ###################################
tee /etc/yum.repos.d/rockyLinux.repo <<-EOF
[baseos]
name=Rocky Linux \$releasever - BaseOS
baseurl=https://mirrors.aliyun.com/rockylinux/\$releasever/BaseOS/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-\$releaserver

[appstream]
name=Rocky Linux \$releasever - AppStream
baseurl=https://mirrors.aliyun.com/rockylinux/\$releasever/AppStream/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-\$releaserver

[crb]
name=Rocky Linux \$releasever - CRB
baseurl=https://mirrors.aliyun.com/rockylinux/\$releasever/CRB/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-\$releaserver

[extras]
name=Rocky Linux \$releasever - Extras
baseurl=https://mirrors.aliyun.com/rockylinux/\$releasever/extras/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-\$releaserver

[devel]
name=Rocky Linux \$releasever - Devel
baseurl=https://mirrors.aliyun.com/rockylinux/\$releasever/devel/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-\$releaserver
EOF

tee /etc/yum.repos.d/epel.repo <<-EOF
[epel]
name=Extra Packages for Linux \$releasever - \$basearch
baseurl=https://mirrors.aliyun.com/epel/\$releasever/Everything/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://mirrors.aliyun.com/epel/RPM-GPG-KEY-EPEL-\$releasever
EOF
##################################### Rocky Linux ###################################


####################################### CentOS #####################################
tee /etc/yum.repos.d/alicloud.repo <<-EOF
[BaseOS]
name=CentOS Stream \$releasever - BaseOS
baseurl=https://mirrors.aliyun.com/centos-stream/\$releasever-stream/BaseOS/x86_64/os/
gpgcheck=1
enabled=1
gpgkey=https://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-Official

[AppStream]
name=CentOS Stream \$releasever - AppStream
baseurl=https://mirrors.aliyun.com/centos-stream/\$releasever-stream/AppStream/x86_64/os/
gpgcheck=1
enabled=1
gpgkey=https://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-Official

[CRB]
name=CentOS Stream \$releasever - CRB
baseurl=https://mirrors.aliyun.com/centos-stream/\$releasever-stream/CRB/x86_64/os/
gpgcheck=1
enabled=1
gpgkey=https://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-Official
EOF

tee /etc/yum.repos.d/epel.repo <<-EOF
[epel]
name=Extra Packages for Linux \$releasever - \$basearch
baseurl=https://mirrors.aliyun.com/epel/\$releasever/Everything/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://mirrors.aliyun.com/epel/RPM-GPG-KEY-EPEL-\$releasever
EOF
####################################### CentOS #####################################


###################################### OpenEuler ###################################
tee > /etc/yum.repos.d/openEuler-huaweiCloud.repo <<-EOF
[openEuler-everything]
name=openEuler 24 - everything
baseurl=http://repo.huaweicloud.com/openeuler/openEuler-24.03-LTS/everything/x86_64/
enabled=1
gpgcheck=1
gpgkey=http://repo.huaweicloud.com/openeuler/openEuler-24.03-LTS/everything/x86_64/RPM-GPG-KEY-openEuler

[openEuler-EPOL]
name=openEuler 24 - epol
baseurl=http://repo.huaweicloud.com/openeuler/openEuler-24.03-LTS/EPOL/main/x86_64/
enabled=1
gpgcheck=0

[openEuler-update]
name=openEuler 24 - update
baseurl=http://repo.huaweicloud.com/openeuler/openEuler-24.03-LTS/update/x86_64/
enabled=1
gpgcheck=0
EOF

tee /etc/yum.repos.d/epel.repo <<-EOF
[epel]
name=Extra Packages for Linux \$releasever - \$basearch
baseurl=https://mirrors.aliyun.com/epel/\$releasever/Everything/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://mirrors.aliyun.com/epel/RPM-GPG-KEY-EPEL-\$releasever
EOF
###################################### OpenEuler ###################################

dnf repolist
dnf makecache --refresh