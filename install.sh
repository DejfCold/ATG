#!/bin/bash

BIN_DIR=~/.local/bin/
SYSTEMD_DIR=~/.config/systemd/user/

mkdir -p ~/apps
mkdir -p ${BIN_DIR}
\cp -r atg.sh ${BIN_DIR}
chmod +x ${BIN_DIR}atg.sh

mkdir -p ${SYSTEMD_DIR}
\cp -r atg.service ${SYSTEMD_DIR}
\cp -r atg.path ${SYSTEMD_DIR}

systemctl --user daemon-reload
systemctl --user enable atg.path --now
