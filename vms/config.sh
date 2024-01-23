#!/bin/bash

sudo apt update
sudo apt install net-tools openssh-server vim tree htop -y

sudo ufw disable
sudo ufw status

# Pod가 Swap을 사용하지 않도록 하여 성능 유지를 위해 SWAP 해제
echo "##################################################"
echo "Swap memory off"
echo "##################################################"
echo

sudo swapoff -a
free
sudo sed -i '/ swap / s/^/#/' /etc/fstab 

# NTP(Network Time Protocol) 설정: k8s cluster는 보통 여러 개의 VM이나 서버로 구성되기 때문에
# 클러스터 내의 모든 Node들은 NTP를 통해서 시간 동기화가 요구됨
echo "##################################################"
echo "NTP Setting"
echo "##################################################"
sudo apt install ntp -y
sudo systemctl restart ntp
sudo systemctl status ntp
echo
echo "##################################################"
echo "Reading NTP"
echo "##################################################"
sudo ntpq -p
echo


echo "##################################################"
echo "IP tables"
echo "##################################################"
sudo -i
echo '1' > /proc/sys/net/ipv4/ip_forward
cat /proc/sys/net/ipv4/ip_forward
echo 
echo "##################################################"
echo "containerd"
echo "##################################################"

# containerd를 이용한 container runtime 구성
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# modprobe 프로그램은 요청된 모듈이 동작할 수 있도록 부수적인 모듈을 depmod 프로그램을 이용하여 검색해
# 필요한 모듈을 커널에 차례로 등록
modprobe overlay
modprobe br_netfilter
echo

echo "##################################################"
echo "bridge setting"
echo "##################################################"
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

cat <<EOF | tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system | grep -i applying


echo "##################################################"
echo "containerd installing and setting"
echo "##################################################"

# k8s runtime  준비 -> containerd, docker, CRI-O 중에 선택이고, 여기서는 containerd 사용
# apt가 HTTPS로 리포지터리를 사용하는 것을 허용하기 위한 패키지 및 docker에 필요한 패키지 설치
sudo apt-get update
sudo apt-get install apt-transport-https ca-certificates curl software-properties-common gnupg2 -y
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sudo docker version

sudo sh -c "containerd config default > /etc/containerd/config.toml"
# sudo vi /etc/containerd/config.toml
# disabled_plugins = []
sudo sed -i 's/ SystemdCgroup = false/ SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd.service

sudo -i
cat <<EOF | tee /etc/docker/daemon.json
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m"
    },
    "storage-driver": "overlay2"
}
EOF

echo
echo "##################################################"
echo "enroll docker service"
echo "##################################################"
sudo mkdir -p /etc/sys
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo usermod -aG docker vagrant
sudo systemctl daemon-reload
sudo systemctl enable docker
sudo systemctl restart docker
sudo systemctl status docker
sudo systemctl restart containerd.service
sudo systemctl status containerd.service

echo
echo
echo "Configuration Config Success!!"

# docker version
# docker info

