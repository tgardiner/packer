#!/usr/bin/env bash
##
# tgardiner: OpenVPN AMI
##
set -ev
export DEBIAN_FRONTEND=noninteractive

# Install dependencies
apt-get -yq install openvpn iptables-persistent

# Enable ip_forward
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf && sysctl -p

# Enable NAT for OpenVPN clients
cat << EOF > /etc/iptables/rules.v4
###
## OpenVPN
###

*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 10.8.0.0/24 -o eth+ -j MASQUERADE
COMMIT

*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT
EOF

# Preserve iptables rules across reboots
systemctl enable netfilter-persistent

# Create chroot dir
mkdir -p /etc/openvpn/jail/tmp

# Download EasyRSA
wget -q https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.8/EasyRSA-3.0.8.tgz
wget -q https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.8/EasyRSA-3.0.8.tgz.sig

# Check file checksum and signature
gpg --import easyrsa-key.asc
if ! gpg --verify EasyRSA-3.0.8.tgz.sig EasyRSA-3.0.8.tgz; then
  echo Invalid file checksum and/or signature
  exit 1
fi

# Extract EasyRSA
tar xzvf EasyRSA-3.0.8.tgz

# Generate CA and certificates
cd EasyRSA-3.0.8/
export EASYRSA_BATCH=1
export EASYRSA_REQ_CN=ca
./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa gen-dh
./easyrsa gen-req server nopass
./easyrsa gen-req client nopass
./easyrsa sign-req server server
./easyrsa sign-req client client

# Place server certificates
cp pki/dh.pem /etc/openvpn/server/dh.pem
cp pki/ca.crt /etc/openvpn/server/ca.crt
cp pki/issued/server.crt /etc/openvpn/server/server.crt
cp pki/private/server.key /etc/openvpn/server/server.key
openvpn --genkey --secret /etc/openvpn/server/ta.key

# Set client certificates
export TLS_AUTH=$(< /etc/openvpn/server/ta.key)
export CA=$(< pki/ca.crt)
export CERT=$(< pki/issued/client.crt)
export KEY=$(< pki/private/client.key)

# Remove temporary CA (just rebuild the ami to rotate keys)
cd ../
rm -rf EasyRSA-3.0.8/

# Place server config
cat << EOF > /etc/openvpn/server.conf
##
# server
##
port 1194
proto udp
dev tun0
chroot jail
ca server/ca.crt
cert server/server.crt
key server/server.key
dh server/dh.pem
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
keepalive 10 120
reneg-sec 86400
inactive 900
tls-auth server/ta.key 0
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
explicit-exit-notify 1
push "redirect-gateway def1"
EOF

# Place client config (you need to change the remote ip)
cat << EOF > /etc/openvpn/client.conf
##
# client
##
remote 0.0.0.0 1194 udp

######### Do not change under this line #########
client
dev tun
proto udp
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3
key-direction 1
auth-nocache
reneg-sec 86400
inactive 900
<tls-auth>
$TLS_AUTH
</tls-auth>
<ca>
$CA
</ca>
<cert>
$CERT
</cert>
<key>
$KEY
</key>
EOF

# Enable OpenVPN on startup
systemctl enable openvpn@server
