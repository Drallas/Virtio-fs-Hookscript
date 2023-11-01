#!/bin/bash

sudo mkdir -p /var/lib/vz/snippets
cd /var/lib/vz/snippets
sudo sh -c "wget https://github.com/Drallas/Virtio-fs-Hookscript/raw/main/Script/virtiofs_hook.pl"
sudo sh -c "wget https://github.com/Drallas/Virtio-fs-Hookscript/raw/main/Script/virtiofs_hook.conf"
sudo chmod +x /var/lib/vz/snippets/virtiofs_hook.pl
