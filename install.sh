#!/bin/bash
set -e

# Variables
K8S_VERSION="1.29.0-00"   # Adjust to your preferred version
CONTAINERD_VERSION="1.7.11" # Example version, can be updated

echo "[1/8] Update system and install dependencies..."
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

echo "[2/8] Disable swap (required for kubelet)..."
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

echo "[3/8] Install containerd..."
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Use systemd cgroup driver (recommended for kubelet)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

echo "[4/8] Add Kubernetes apt repository..."
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/kubernetes.gpg
echo "deb https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

echo "[5/8] Install kubeadm, kubelet, kubectl..."
sudo apt-get update -y
sudo apt-get install -y kubelet=${K8S_VERSION} kubeadm=${K8S_VERSION} kubectl=${K8S_VERSION}
sudo apt-mark hold kubelet kubeadm kubectl

echo "[6/8] Enable and start kubelet..."
sudo systemctl enable kubelet
sudo systemctl start kubelet

echo "[7/8] Initialize Kubernetes control plane (only on master node)..."
# Replace with your network CIDR if using a CNI like Calico/Flannel
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

echo "[8/8] Configure kubectl for the current user..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "✅ Kubernetes installation complete!"
echo "👉 Next: install a CNI plugin, e.g., Flannel:"
echo "   kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"
