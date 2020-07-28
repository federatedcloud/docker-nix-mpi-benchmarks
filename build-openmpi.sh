#!/bin/bash

## Generate ssh keys
if [ -d "ssh" ]; then
  chmod u+rw -R ssh
  rm -rf ssh
fi

mkdir -p ssh
cd ssh && ssh-keygen -t rsa -f id_rsa.mpi -N '' && cd ..

cat > ssh/config <<EOF
StrictHostKeyChecking no
PasswordAuthentication no
Host c1
    Hostname x.x.x.x
    Port 2222
    User nixuser
    IdentityFile /home/nixuser/.ssh/id_rsa
Host c2
    Hostname x.x.x.x
    Port 2222
    User nixuser
    IdentityFile /home/nixuser/.ssh/id_rsa
Host bitbucket.org
    IdentityFile /home/nixuser/tmp_rsa
EOF

chmod 700 ssh && chmod 600 ssh/*

## OS env vars
export BASEIMG="alpine:3.7"
export ADDUSER="adduser -D -g \"\""
export DISTRO_INSTALL_CMDS="alpine_install_cmds.sh"

## Append testing for uncommitted changes
git_image_tag()
{
    local commit
    commit=$(git rev-parse --verify HEAD)
    local tag="$commit"
    if [ ! -z "$(git status --porcelain)" ]; then
	tag="${commit}_testing"
    fi
    
    echo "$tag"
}
# Uncomment to test from command line:
#git_image_tag

## Docker image tagging
REPO="cornellcac/nix-mpi-benchmarks"
TAG=$(git_image_tag)
export NIX_OMPI_IMAGE="${REPO}:${TAG}"
echo "NIX_OMPI_IMAGE is $NIX_OMPI_IMAGE"
docker build \
       --build-arg ADDUSER="$ADDUSER" \
       -t "$NIX_OMPI_IMAGE" -f Dockerfile .

#       --build-arg BASEOS="$BASEOS" \
#       --build-arg SSH_PRIVATE_KEY="$(cat ${BITBUCKET_SSH_KEY:="$HOME/.ssh/id_rsa"})" \


#TEST_IMG="${REPO}:${TAG}_TEST"
#docker create --name "$TEST_IMG" "$NIX_OMPI_IMAGE"
#docker cp "$TEST_IMG:/tmp/.nix_versions" Docker/
#docker cp "$TEST_IMG:/tmp/env_backup.drv" Docker/
#docker rm -f "$TEST_IMG"
