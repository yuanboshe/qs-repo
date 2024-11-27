#!/bin/bash
# 安装 docker
if ! command -v docker &>/dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun

  # 使当前用户能够有权限执行docker相关指令
  if ! getent group docker &>/dev/null; then
    echo "Adding 'docker' group..."
    sudo groupadd docker
  fi
  if ! getent group "$USER" docker &>/dev/null; then
    echo "Granting '$USER' to 'docker' group..."
    sudo usermod -aG docker "$USER"
  else
    echo "'$USER' is already a member of the 'docker' group."
  fi

  # Docker Hub加速
  if [ -f "${WORK_PATH}/templates/daemon.json" ]; then
    sudo cp "${WORK_PATH}/templates/daemon.json" /etc/docker/daemon.json
  else
    echo "daemon.json not found in ${WORK_PATH}/templates/"
  fi
  sudo systemctl restart docker

  echo "Docker installation is complete. Please log out and log back in to apply group membership changes."
else
  echo "Docker is already installed."
fi
