#!/usr/bin/env bash

cd

touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
ssh-keygen -t ed25519
#cat ~/.ssh/id_.pub >> ~/.ssh/authorized_key
#chmod 600 ~/.ssh/authorized_keys

# sshd (/etc/init.d/sshd restart or service sshd restart)
