#!/bin/bash
mount_dir=/home/jhkim/shared/
image_name="192.168.57.60:8008/sdk_release/xcena_sdk_81c21@sha256:cd848f566914203014e8dcf0b07f0c9bff7b3d2c13079df0c705e0b065ed95fc"

# check mount dir
if [ -d "$mount_dir" ]; then
    echo "$mount_dir will be mounted as /shared in the container"
else
    echo "$mount_dir does not exist"
    exit 1
fi

# export github token for github copilot cli
BASH_SOURCE_VAR="${BASH_SOURCE[0]}"
REL_SCRIPT_PATH="$(dirname $BASH_SOURCE_VAR)"
SCRIPT_PATH="$(cd $REL_SCRIPT_PATH && pwd)"
TOKEN=$(cat $SCRIPT_PATH/token.txt)
echo $TOKEN

if [ -z "$TOKEN" ]; then
    echo "fill your token into ${SCRIPT_PATH}/token.txt"
    exit 1
fi

# name: jhkim{yymmdd}
date_str=$(date +%y%m%d)
container_name=jhkim${date_str}
# if container exists, add a suffix number
if [ "$(docker ps -a -q -f name=^/${container_name}$)" ]; then
  suffix=1
  while [ "$(docker ps -a -q -f name=^/${container_name}_${suffix}$)" ]; do
    suffix=$((suffix + 1))
  done
  container_name=${container_name}_${suffix}
fi
docker run -dit \
 --name $container_name \
 -v /home/jhkim/shared:/shared/   \
 -v ~/.gitconfig:/root/.gitconfig \
  -v $HOME/.ssh:/root/.ssh:ro \
  -v ~/.config/github-copilot:/root/.config/github-copilot \
  -e GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
  -e GIT_AUTHOR_NAME="jhkim-XCENA" \
  -e GIT_AUTHOR_EMAIL="jeongho.kim@xcena.com" \
  -e GIT_COMMITTER_NAME="jhkim-XCENA" \
  -e GIT_COMMITTER_EMAIL="jeongho.kim@xcena.com" \
  -e GITHUB_TOKEN=$TOKEN \
  -e LANG=C.UTF-8 \
  -e LC_ALL=C.UTF-8 \
--device=/dev/kvm --cap-add=SYS_ADMIN -e USER=$USER ${image_name}

echo "Launched container: $container_name"
echo "docker exec -it $container_name bash"


