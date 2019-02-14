#!/bin/bash
# generalize_El6.sh - A simple script to prepare a CentOS6 linux server for cloning
# Michael Brown 2016 <strictly.sysops@gmail.com>


# test for yum-utils (required for kernel cleanup)
if [[ -z $(rpm -qa | grep yum-utils) ]]; then
   yum -y install yum-utils
fi

echo "stop services..."
/sbin/service rsyslog stop
/sbin/service auditd stop
echo "ok"

echo "cleanup old kernels..."
/usr/bin/package-cleanup -y --oldkernels --count=1
echo "ok"

echo "cleanup package manager..."
/usr/bin/yum clean all
rm -rfv /var/cache/yum
echo "ok"

echo "force a log rotations and cleanup..."
/usr/sbin/logrotate –f /etc/logrotate.conf
/bin/rm -fv /var/log/*.gz
/bin/rm -fv /var/log/dmesg*
/bin/rm -fv /var/log/anaconda*
echo "ok"

echo "truncate the audit logs..."
/bin/cat /dev/null > /var/log/audit/audit.log
/bin/cat /dev/null > /var/log/wtmp
/bin/cat /dev/null > /var/log/lastlog
echo "ok"

echo "remove persistent rules, hostname and hardware addresses for networking..."
/bin/rm -fv /etc/udev/rules.d/70*
/bin/sed -i '/^HOSTNAME/d' /etc/sysconfig/network 
/bin/sed -i '/^HWADDR/d' /etc/sysconfig/network-scripts/ifcfg-eth0
/bin/sed -i '/^UUID/d' /etc/sysconfig/network-scripts/ifcfg-eth0
echo "ok"

echo "cleanup temp..."
/bin/rm –rfv /tmp/*
/bin/rm –rfv /var/tmp/*
echo "ok"

echo "remove the system SSH keys..."
/bin/rm –fv /etc/ssh/ssh*key*
echo "ok"

echo "cleanup the root users history and keys..."
unset HISTFILE
/bin/rm -fv ~root/.bash_history
/bin/rm -rfv ~root/.ssh/
/bin/rm -fv ~root/anaconda-ks.cfg
/bin/rm -fv ~root/install.log*
/bin/rm -fv ~root/post_install.log
echo "ok"

echo "set SELinux to permissive and relabel on next boot..."
/bin/sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
/bin/touch /.autorelabel
echo "ok"

echo "make sure custom files have appropriate permissions"
chmod +x /usr/local/bin/*.sh
chmod 400 /root/.mapsvc

echo "This server is ready to become a template, powering down NOW..."
/bin/sleep 3
/bin/rm -f ./generalize.sh
/sbin/shutdown -h now
exit 0