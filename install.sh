#!/bin/bash

clear
echo "=================================="
echo "     COMP_MANIYA KASKAD"
echo " Telegram: https://t.me/computerchik"
echo "=================================="

apt update -y
apt install -y iptables-persistent netfilter-persistent qrencode curl

sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

read -p "Входной порт на этом VPS: " IN_PORT
read -p "IP удаленного VPS: " REMOTE_IP
read -p "Удаленный порт: " REMOTE_PORT

iptables -t nat -A PREROUTING -p tcp --dport $IN_PORT -j DNAT --to-destination $REMOTE_IP:$REMOTE_PORT
iptables -t nat -A POSTROUTING -j MASQUERADE
iptables -A FORWARD -p tcp -d $REMOTE_IP --dport $REMOTE_PORT -j ACCEPT

netfilter-persistent save

TG_LINK="https://t.me/computerchik"

echo
echo "=================================="
echo " KASKAD ГОТОВ"
echo " $IN_PORT -> $REMOTE_IP:$REMOTE_PORT"
echo " Telegram: $TG_LINK"
echo "=================================="

echo
echo "QR код Telegram:"
qrencode -t ANSIUTF8 "$TG_LINK"
