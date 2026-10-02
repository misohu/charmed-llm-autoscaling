#!/usr/bin/env bash
# Prepare a fresh Ubuntu 24.04 (noble) GPU VM for the demo:
#   - Helm, Terraform, concierge and Juju
#   - Canonical Kubernetes + Juju (bootstrapped by concierge)
#   - the NVIDIA GPU Operator (installs the container toolkit + device plugin)
#
# Run this on the VM as the 'ubuntu' user, from a directory that contains the
# concierge.yaml from this repo (edit its load-balancer CIDR first).
set -euo pipefail

echo "== Install Helm =="
sudo apt-get update
sudo apt-get install -y curl gpg apt-transport-https
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey \
  | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
  | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm

echo "== Install snaps: terraform, concierge, juju =="
sudo snap install terraform --channel latest/stable --classic
sudo snap install concierge --classic
sudo snap install juju --channel 3.6/stable --classic

echo "== Bootstrap Kubernetes + Juju with concierge =="
# Uses ./concierge.yaml from the current directory.
sudo concierge prepare --trace

echo "== Install the NVIDIA GPU Operator =="
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm install --generate-name -n gpu-operator-resources --create-namespace nvidia/gpu-operator

echo "== Wait for the GPU operator validation to pass =="
until kubectl logs -n gpu-operator-resources -l app=nvidia-operator-validator 2>/dev/null \
      | grep -q "all validations are successful"; do
  echo "  ...waiting for GPU operator validation"
  kubectl get pods -n gpu-operator-resources || true
  sleep 60
done

echo
echo "Done. GPUs now available to Kubernetes:"
kubectl get nodes -o jsonpath='{.items[0].status.capacity.nvidia\.com/gpu}'; echo
