#!/bin/bash

# Script to setup and run OpenConnect server on Ubuntu 16.04
# By: Mohammad H. Shahin
# email: mhshahin91@gmail.com

# Check if the script runs by sudo
if [[ $UID != 0 ]]; then
	echo "Please run this script with sudo:"
	echo "sudo $0 $*"
	exit 1
fi

# Get IP address of the first network interface
IP=$(ifconfig | grep 'inet addr:' | cut -d: -f2 | awk 'NR==1 {print $1}')

echo "Downloading the latest version of ocserv and extracting..."
sleep 2
wget ftp://ftp.infradead.org/pub/ocserv/ocserv-0.9.2.tar.xz
tar -xf ocserv-0.9.2.tar.xz
cd ocserv-0.9.2

echo "Installing the dependencies..."
sleep 2
apt-get install -y build-essential pkg-config libgnutls28-dev libwrap0-dev libpam0g-dev libseccomp-dev libreadline-dev libnl-route-3-dev

echo "Configuring and Installing..."
sleep 2
./configure
make
make install

echo "Installing dependencies and Generating Keys..."
sleep 2
apt-get install -y gnutls-bin
mkdir certificates
cd certificates

read -p "Enter VPN Name: " vpn_name
read -p "Enter ORG Name: " org_name

cat << _EOF_ > ca.tmpl
cn = ${vpn_name}
organization = ${org_name}
serial = 1
expiration_days = 3650
ca
signing_key
cert_signing_key
crl_signing_key
_EOF_

certtool --generate-privkey --outfile ca-key.pem
certtool --generate-self-signed --load-privkey ca-key.pem --template ca.tmpl --outfile ca-cert.pem

cat << _EOF_ > server.tmpl
cn = ${IP}
organization = ${org_name}
expiration_days = 3650
signing_key
encryption_key
tls_www_server
_EOF_

certtool --generate-privkey --outfile server-key.pem
certtool --generate-certificate --load-privkey server-key.pem --load-ca-certificate ca-cert.pem --load-ca-privkey ca-key.pem --template server.tmpl --outfile server-cert.pem

CONF_FILE=/etc/ocserv
mkdir ${CONF_FILE}
cp server-cert.pem server-key.pem ${CONF_FILE}
cd ../doc
cp sample.config ${CONF_FILE}/config
cd ${CONF_FILE}

sed -i "s#./sample.passwd#${CONF_FILE}/ocpasswd#g" "${CONF_FILE}/config"
sed -i 's$#cisco-client-compat = true$cisco-client-compat = true$g' "${CONF_FILE}/config"
sed -i "s#try-mtu-discovery = false#try-mtu-discovery = true#g" "${CONF_FILE}/config"
sed -i "s#server-cert = ../tests/server-cert.pem#server-cert = ${CONF_FILE}/server-cert.pem#g" "${CONF_FILE}/config"
sed -i "s#server-key = ../tests/server-key.pem#server-key = ${CONF_FILE}/server-key.pem#g" "${CONF_FILE}/config"
sed -i "s/dns = 192.168.1.2/dns = 4.2.2.4\ndns = 8.8.8.8/g" "${CONF_FILE}/config"
sed -i 's$route = 192.168.1.0/255.255.255.0$#route = 192.168.1.0/255.255.255.0$g' "${CONF_FILE}/config"
sed -i 's$route = 192.168.5.0/255.255.255.0$#route = 192.168.5.0/255.255.255.0$g' "${CONF_FILE}/config"
sed -i 's$no-route = 192.168.5.0/255.255.255.0$#no-route = 192.168.5.0/255.255.255.0$g' "${CONF_FILE}/config"
sed -i 's$#net.ipv4.ip_forward=1$net.ipv4.ip_forward=1$g' "/etc/sysctl.conf"

read -p "Enter User: " USER
ocpasswd -c ${CONF_FILE}/ocpasswd ${USER}

iptables -t nat -A POSTROUTING -j MASQUERADE

sysctl -p /etc/sysctl.conf

ocserv -c ${CONF_FILE}/config
