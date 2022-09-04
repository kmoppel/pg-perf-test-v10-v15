#!/bin/bash

set -e

# First part from https://wiki.postgresql.org/wiki/Apt
sudo apt update >/dev/null && sudo apt install -y curl ca-certificates gnupg >/dev/null
curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
sudo sed -i -E  's/^(.*)$/\1 15/' /etc/apt/sources.list.d/pgdg.list
sudo apt update >/dev/null
sudo apt install -y postgresql-1{0,1,2,3,4,5} tmux rsync >/dev/null

for x in {10..15} ; do sudo pg_dropcluster --stop $x main ; done
