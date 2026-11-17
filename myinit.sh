#!/bin/bash
#------------
#setup username/password
#------------
echo root:You22kme#12345 | sudo chpasswd root
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config;
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config;
sudo service sshd restart

#------------
#setup tm earnfm-client repocket
#------------
sudo apt update  -y
curl -fsSL https://raw.githubusercontent.com/kungwu222/scripts-hub/refs/heads/main/guaji.sh | sudo bash

#------------
#clear log, setup proxy, setup f2ban
#------------
sudo wget -qO- -o- https://raw.githubusercontent.com/ooplastone22/log_clean/refs/heads/main/log_clean.sh | sudo bash
sudo curl -fsSL https://raw.githubusercontent.com/kungwu222/sing-box-go/refs/heads/main/install.sh | sudo bash -s -- --name "Init-node"
sudo sbgo add socks 8050 4691d36a 3d5f00746a6b --name "Init-node-socks"
curl -sL https://raw.githubusercontent.com/kungwu222/f2ban/main/install3.sh | sudo bash
