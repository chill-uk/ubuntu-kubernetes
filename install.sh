#!/bin/bash
set -e

ROLE="${1:-master}"

usage() {
    echo "Usage: $0 [master|node]"
    exit 1
}

if [[ $ROLE != "master" && $ROLE != "node" ]]; then
    usage
fi

info() {
    echo -e "\033[1;32m$1\033[0m"
}
warn() {
    echo -e "\033[1;33m$1\033[0m"
}
error() {
    echo -e "\033[1;31m$1\033[0m"
}

info "[1/8] Updating system and installing dependencies..."
sudo apt update
sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

info "[2/8] Disabling swap (required for kubelet)..."
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

info "[3/8] Loading required kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

info "[4/8] Setting system networking parameters..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

info "[5/8] Installing containerd..."
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Use systemd cgroup driver for kubelet compatibility
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

info "[6/8] Adding Kubernetes apt repository and key..."
if [[ ! -d /etc/apt/keyrings ]]; then
    sudo mkdir -p -m 755 /etc/apt/keyrings
fi
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list

info "[7/8] Installing kubeadm, kubelet, kubectl..."
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

info "[8/8] Enabling and starting kubelet..."
sudo systemctl enable kubelet
sudo systemctl start kubelet

if [[ $ROLE == "master" ]]; then
    info "[9/8] Initializing Kubernetes control plane (master node)..."
    # Using Flannel's default network CIDR; adjust if needed
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16

    info "[10/8] Configuring kubectl for the current user..."
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    info "✅ Kubernetes master installation complete!"
    info "👉 Next: install a CNI plugin, e.g., Flannel:"
    echo "   kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"
    warn "To add worker nodes, run the join command given by 'kubeadm init' here on each node."
else
    warn "[SKIP] Master initialization. This node will join an existing cluster."
    info "To join this node, use the kubeadm join command supplied by the master node."
    warn "Sample: sudo kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>"
fi
