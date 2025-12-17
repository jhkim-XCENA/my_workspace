#!/bin/bash
image_name=xcenadev/sdk:latest

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
  -e GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
  -v ~/.config/github-copilot:/root/.config/github-copilot \
  -e LANG=C.UTF-8 \
  -e LC_ALL=C.UTF-8 \
--device=/dev/kvm --cap-add=SYS_ADMIN -e USER=$USER xcenadev/sdk:latest

echo "Launched container: $container_name"
echo "docker exec -it $container_name /bin/bash"


