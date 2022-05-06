#!/usr/bin/env bash

function info { echo -e "\e[32m[info] $*\e[39m"; }
function warn  { echo -e "\e[33m[warn] $*\e[39m"; }
function error { echo -e "\e[31m[error] $*\e[39m"; exit 1; }

PREFIX=${PREFIX:-/usr}
DATA_SHARE=${DATA_SHARE:-$PREFIX/share/hassio}

info "Stopping and disabling services"

systemctl daemon-reload
systemctl stop hassio-supervisor.service
systemctl disable hassio-supervisor.service
systemctl stop hassio-apparmor.service
systemctl disable hassio-apparmor.service
systemctl stop haos-agent.service
systemctl disable haos-agent.service
systemctl daemon-reload

info "Removing dockers"
docker ps -a | grep -E '(homeassistant|hassio_)' | awk '{print $1}' | xargs -L 1 docker rm -f

info "Removing configurations"

rm -rf "$DATA_SHARE"
rm -f /etc/dbus-1/system.d/io.hass.conf
rm -f /etc/systemd/system/haos-agent.service
rm -f /etc/systemd/system/hassio-apparmor.service
rm -f /etc/systemd/system/hassio-supervisor.service
# rm -f /etc/docker/daemon.json
# rm -f /etc/NetworkManager/system-connections/default
# rm -f /etc/NetworkManager/NetworkManager.conf
# rm -f /etc/network/interfaces

info "Removing binaries"

rm -f /usr/bin/ha
rm -f /usr/sbin/hassio-apparmor
rm -f /usr/sbin/hassio-supervisor
rm -f /usr/share/hassio/apparmor/hassio-supervisor
rm -f /usr/bin/os-agent
