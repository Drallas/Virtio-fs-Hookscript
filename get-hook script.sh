#!/bin/bash

sudo mkdir -p /var/lib/vz/snippets
sudo sh -c "curl https://github.com/Drallas/Virtio-fs-Hookscript-/raw/main/Script/virtiofs-hook.pl"
sudo sh -c "https://github.com/Drallas/Virtio-fs-Hookscript-/raw/main/Script/virtiofs_hook.conf"
sudo chmod +x /var/lib/vz/snippets/virtiofs-hook.pl
