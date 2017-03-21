#!/bin/bash

# env variables
MASTER_IP=$1
MASTER_NAME=$2
NODE_NAME=`hostname`
IP=`ip addr | grep "state UP" -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/'`

echo "Provisioning network on Maya Host"
set -e

FLANNEL_VER="v0.6.2"
FLANNEL_DOWNLOAD_URL=https://github.com/coreos/flannel/releases/download
CURDIR=`pwd`

cd /tmp/

if [ ! -f "./tmp/flannel-${FLANNEL_VER}-linux-amd64.tar.gz" ]; then
  echo "Fetching flannel ${FLANNEL_VER} ..."
  curl -sSL ${FLANNEL_DOWNLOAD_URL}/${FLANNEL_VER}/flannel-${FLANNEL_VER}-linux-amd64.tar.gz -o flannel-${FLANNEL_VER}-linux-amd64.tar.gz
fi

echo "Installing flannel ${FLANNEL_VER} ..."
tar xzvf flannel-${FLANNEL_VER}-linux-amd64.tar.gz
sudo chmod +x flanneld
sudo mv flanneld /usr/local/bin/flanneld

cat <<EOF >/tmp/flannel-config.json
{
    "Network": "10.200.0.0/16",
    "SubnetLen": 24,
    "Backend": {
        "Type": "vxlan",
        "Port": 8285
     }
}
EOF

sudo mv /tmp/flannel-config.json /etc/flannel-config.json

# Import default configuration into etcd for maya master
# etcdctl --ca-file=/etc/etcd/ca.crt set /coreos.com/network/config < /etc/flannel-config.json

# Creating certs dir and setting up permissions
mkdir -p /etc/etcd/

cat <<EOF > /tmp/flanneld.service
[Unit]
Description=Flannel SDN
Documentation=https://github.com/coreos/flannel

[Service]
ExecStart=/usr/local/bin/flanneld \
  --iface=enp0s8 \
  --etcd-cafile=/etc/etcd/ca.crt \
  --etcd-endpoints=https://$MASTER_NAME:2379
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# creating flanneld daemon service
sudo mv /tmp/flanneld.service /etc/systemd/system/flanneld.service

# Setup hosts file to support ping by hostname to each node in the cluster
cp /etc/hosts /tmp/
if [ ! "$(cat /tmp/hosts | grep $IP)" ]; then
        echo "Adding $NODE_NAME to hosts file"
     echo "$IP $NODE_NAME" >> /tmp/hosts
fi  
echo "Adding $MASTER_NAME to hosts file"
echo "$MASTER_IP $MASTER_NAME" >> /tmp/hosts
sudo mv /tmp/hosts /etc/

# Start flannel
echo "Starting flannel service..."
   sudo systemctl enable flanneld
   sudo systemctl start flanneld

echo "Network configuration verified"

echo "Changing the configuration of docker"

# Setup docker env file for 
mkdir -p /etc/etcd/cni/
cat <<EOF > /tmp/docker_opts.env
DOCKER_OPT_BIP=""
DOCKER_OPT_IPMASQ=""
EOF

sudo mv /tmp/docker_opts.env /run/

# Configuring Docker service
cat <<EOF > /tmp/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io
After=flanneld.service

[Service]
EnvironmentFile=/run/docker_opts.env
EnvironmentFile=/run/flannel/subnet.env
ExecStart=/usr/bin/dockerd --bip=${FLANNEL_SUBNET} --mtu=${FLANNEL_MTU}  --iptables=false   --ip-masq=false   --host=unix:///var/run/docker.sock   --log-level=error   --storage-driver=overlay
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# creating flanneld daemon service
sudo mv /tmp/docker.service /etc/systemd/system/docker.service 

# Starting Docker service
echo "Starting docker service..."
   sudo systemctl daemon-reload
   sudo systemctl restart docker.service
