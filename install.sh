#!/bin/bash

set -x

ipaddr=${1}
ggsnaddr=${2}
stagedir=".staging"

fqdn="mm01.epc.mnc01.mcc001.3gppnetwork.org"
domain=${fqdn#*.*}
mcc=001
mnc=01

if [ -z "${ipaddr}" -o -z "${ggsnaddr}" ]; then
  echo "Usage: %{0} <ip address> <ggsn ip address>"
  exit 1
fi

# copy to staging directory
rm -rf ${stagedir}
mkdir -p ${stagedir}
cp osmocom/*.cfg ${stagedir}/
cp open5gs/*.yaml ${stagedir}/
cp freeDiameter/*.conf freeDiameter/*.pem ${stagedir}/

sed -i -e "s/{ip}/${ipaddr}/g" ${stagedir}/*
sed -i -e "s/{ggsnip}/${ggsnaddr}/g" ${stagedir}/*
sed -i -e "s/{mcc}/${mcc}/g" ${stagedir}/*
sed -i -e "s/{mnc}/${mnc}/g" ${stagedir}/*
sed -i -e "s/{fqdn}/${fqdn}/g" ${stagedir}/*
sed -i -e "s/{domain}/${domain}/g" ${stagedir}/*

# install config
cp ${stagedir}/*.cfg /etc/osmocom/
cp ${stagedir}/*.yaml /etc/open5gs/
cp ${stagedir}/*.conf ${stagedir}/*.pem /etc/freeDiameter/

# open5gs needs to be able to read these, but other stuff shouldn't
chown open5gs:open5gs /etc/freeDiameter/*.pem

# add fqdn to hosts for Open5gs MME
if ! grep -q "${fqdn}" "/etc/hosts" >/dev/null; then
    echo "${ggsnaddr}   ${fqdn}" >> /etc/hosts
fi

# restart services
systemctl restart osmo-ggsn
systemctl restart osmo-hlr
systemctl restart osmo-hnbgw
systemctl restart osmo-mgw
systemctl restart osmo-msc
systemctl restart osmo-sgsn
systemctl restart osmo-stp
systemctl restart osmo-upf

systemctl start mongod.service
mongosh open5gs-mongo-admin-account.js

systemctl restart open5gs-hssd.service
systemctl restart open5gs-mmed.service
systemctl restart open5gs-sgwcd.service
systemctl restart open5gs-sgwud.service
systemctl restart open5gs-amfd.service
systemctl restart open5gs-upfd.service
systemctl restart open5gs-nrfd.service
systemctl restart open5gs-ausfd.service
systemctl restart open5gs-udmd.service
systemctl restart open5gs-udrd.service
systemctl restart open5gs-bsfd.service
systemctl restart open5gs-pcrfd.service
systemctl restart open5gs-smfd.service
systemctl restart open5gs-nssfd.service
systemctl restart open5gs-pcfd.service
systemctl restart open5gs-webui.service

