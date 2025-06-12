#!/bin/bash

set -x

ipaddr=${1}
ggsnaddr=${2}
upfaddr=${3:-127.0.0.7}
v4upfaddr="10.45.0.1"
v4upfprefix="16"
v6upfaddr="2001:db8:cafe::1"
v6upfprefix="48"
stagedir=".staging"

domain="epc.mnc01.mcc001.3gppnetwork.org"
mcc=001
mnc=01

if [ -z "${ipaddr}" -o -z "${ggsnaddr}" ]; then
  echo "Usage: %{0} <ip address> <ggsn ip address> [<upf ip address>]"
  exit 1
fi

# copy to staging directory
rm -rf ${stagedir}
mkdir -p ${stagedir}
cp osmocom/*.cfg ${stagedir}/
cp open5gs/*.yaml ${stagedir}/
cp freeDiameter/*.conf ${stagedir}/

openssl req -new -batch -x509 -days 3650 -nodes     \
   -newkey rsa:1024 -out "${stagedir}/cert.pem" -keyout "${stagedir}/privkey.pem" \
   -subj /CN="mme.${domain}" -addext "subjectAltName = DNS:*.${domain}"

sed -i -e "s/{mcc}/${mcc}/g" ${stagedir}/*
sed -i -e "s/{mnc}/${mnc}/g" ${stagedir}/*
sed -i -e "s/{domain}/${domain}/g" ${stagedir}/*

# Only used for Osmocom GTP
sed -i -e "s/{ggsnip}/${ggsnaddr}/g" ${stagedir}/*
# Used for everything else plus Open5gs SGW-U
sed -i -e "s/{ip}/${ipaddr}/g" ${stagedir}/*

# Open5gs UPF GTP-U
sed -i -e "s/{upfip}/${upfaddr}/g" ${stagedir}/*
v4upfsubnet=$(ipcalc -n "${v4upfaddr}/${v4upfprefix}" | sed 's/NETWORK=//g')
v6upfsubnet=$(ipcalc -n "${v6upfaddr}/${v6upfprefix}" | sed 's/NETWORK=//g')
sed -i -e "s/{v4upfsubnet}/${v4upfsubnet}/g" ${stagedir}/*
sed -i -e "s/{v4upfprefix}/${v4upfprefix}/g" ${stagedir}/*
sed -i -e "s/{v4upfaddr}/${v4upfaddr}/g" ${stagedir}/*
sed -i -e "s/{v6upfsubnet}/${v6upfsubnet}/g" ${stagedir}/*
sed -i -e "s/{v6upfprefix}/${v6upfprefix}/g" ${stagedir}/*
sed -i -e "s/{v6upfaddr}/${v6upfaddr}/g" ${stagedir}/*

# install config and certificates
cp ${stagedir}/*.cfg /etc/osmocom/
cp ${stagedir}/*.yaml /etc/open5gs/
cp ${stagedir}/*.conf /etc/freeDiameter/
cp ${stagedir}/*.pem /etc/freeDiameter/

# open5gs needs to be able to read these, but other stuff shouldn't
chown open5gs:open5gs /etc/freeDiameter/*.pem

# add fqdns to hosts file
declare -a hnames=("hss"       "mme"         "pcrf"      "smf")
declare -a haddrs=("127.0.0.8" "${ggsnaddr}" "127.0.0.9" "127.0.0.4")
for (( i=0; i<${#hnames[@]}; i++ )); do
  if ! grep -q "${hnames[$i]}.${domain}" "/etc/hosts" >/dev/null; then
    echo "${haddrs[$i]}   ${hnames[$i]}.${domain}" >> /etc/hosts
  fi
done

ogsuid=`id -u open5gs`
ogsgid=`id -g open5gs`
if [ -z "${ogsuid}" -o -z "${ogsgid}" ]; then
  echo "Failed to read Open5gs user and group IDs"
  exit 1
fi
if ! nmcli con show ogstun &> /dev/null; then
  nmcli con add type tun \
    ifname ogstun \
    con-name ogstun \
    mode tun \
    owner "${ogsuid}" \
    group "${ogsgid}" \
    autoconnect true \
    ip4 "${v4upfaddr}/${v4upfprefix}" \
    ip6 "${v6upfaddr}/${v6upfprefix}"
fi

# restart osmocom services
#for svc in ggsn hlr hnbgw mgw msc sgsn stp upf; do
#  systemctl restart "osmo-${svc}"
#done

systemctl start mongod.service
mongosh open5gs-mongo-admin-account.js

# restart open5gs services
for svc in hssd mmed sgwcd sgwud amfd upfd nrfd ausfd udmd udrd bsfd pcrfd smfd nssfd pcfd scpd webui; do
  systemctl restart "open5gs-${svc}"
done

firewall-cmd --permanent --zone=FedoraWorkstation --add-port=36412/sctp
firewall-cmd --permanent --zone=public --add-port=36412/sctp
systemctl restart firewalld
