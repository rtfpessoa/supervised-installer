#!/usr/bin/env bash

set -e

function info { echo -e "\e[32m[info] $*\e[39m"; }
function warn  { echo -e "\e[33m[warn] $*\e[39m"; }
function error { echo -e "\e[31m[error] $*\e[39m"; exit 1; }

warn ""
warn "If you want more control over your own system, run"
warn "Home Assistant as a VM or run Home Assistant Core"
warn "via a Docker container."
warn ""

# Check if Modem Manager is enabled
if systemctl is-enabled ModemManager.service &> /dev/null; then
    warn "ModemManager service is enabled. This might cause issue when using serial devices."
fi

# Check dmesg access
if [[ "$(sysctl --values kernel.dmesg_restrict)" != "0" ]]; then
    info "Fix kernel dmesg restriction"
    echo 0 > /proc/sys/kernel/dmesg_restrict
    echo "kernel.dmesg_restrict=0" >> /etc/sysctl.conf
fi

cp -f ./etc/docker/daemon.json /etc/docker/daemon.json
cp -f ./etc/NetworkManager/system-connections/default /etc/NetworkManager/system-connections/default
cp -f ./etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf
cp -f ./etc/systemd/system/hassio-apparmor.service /etc/systemd/system/hassio-apparmor.service
cp -f ./etc/systemd/system/hassio-supervisor.service /etc/systemd/system/hassio-supervisor.service
mkdir -p /etc/network
cp -f ./etc/network/interfaces /etc/network/interfaces

cp -f ./usr/bin/ha /usr/bin/ha
cp -f ./usr/sbin/hassio-apparmor /usr/sbin/hassio-apparmor
cp -f ./usr/sbin/hassio-supervisor /usr/sbin/hassio-supervisor
mkdir -p /usr/share/hassio/apparmor
cp -f ./usr/share/hassio/apparmor/hassio-supervisor /usr/share/hassio/apparmor/hassio-supervisor

ARCH=$(uname -m)

BINARY_DOCKER=/usr/bin/docker

DOCKER_REPO="ghcr.io/home-assistant"

SERVICE_DOCKER="docker.service"
SERVICE_NM="NetworkManager.service"

# Read infos from web
URL_VERSION_HOST="version.home-assistant.io"
URL_VERSION="https://version.home-assistant.io/stable.json"
HASSIO_VERSION=$(curl -s ${URL_VERSION} | jq -e -r '.supervisor')
URL_APPARMOR_PROFILE="https://version.home-assistant.io/apparmor.txt"

# Restart NetworkManager
info "Restarting NetworkManager"
systemctl restart "${SERVICE_NM}"

# Enable and start systemd-resolved
if [ "$(systemctl is-active systemd-resolved)" = 'inactive' ]; then
    info "Enable systemd-resolved"
    systemctl enable systemd-resolved.service> /dev/null 2>&1;
    systemctl start systemd-resolved.service> /dev/null 2>&1;
fi

# Restart Docker service
info "Restarting docker service"
systemctl restart "${SERVICE_DOCKER}"

# Check network connection
while ! ping -c 1 -W 1 ${URL_VERSION_HOST}; do
    info "Waiting for ${URL_VERSION_HOST} - network interface might be down..."
    sleep 2
done

# Get primary network interface
PRIMARY_INTERFACE=$(ip route | awk '/^default/ { print $5 }')
IP_ADDRESS=$(ip -4 addr show dev "${PRIMARY_INTERFACE}" | awk '/inet / { sub("/.*", "", $2); print $2 }')

case ${ARCH} in
    "i386" | "i686")
        MACHINE=${MACHINE:=qemux86}
        HASSIO_DOCKER="${DOCKER_REPO}/i386-hassio-supervisor"
    ;;
    "x86_64")
        MACHINE=${MACHINE:=qemux86-64}
        HASSIO_DOCKER="${DOCKER_REPO}/amd64-hassio-supervisor"
    ;;
    "arm" |"armv6l")
        if [ -z "${MACHINE}" ]; then
             db_input critical ha/machine-type || true
             db_go || true
             db_get ha/machine-type || true
             MACHINE="${RET}"
             db_stop
        fi
        HASSIO_DOCKER="${DOCKER_REPO}/armhf-hassio-supervisor"
    ;;
    "armv7l")
        if [ -z "${MACHINE}" ]; then
             db_input critical ha/machine-type || true
             db_go || true
             db_get ha/machine-type || true
             MACHINE="${RET}"
             db_stop
        fi
        HASSIO_DOCKER="${DOCKER_REPO}/armv7-hassio-supervisor"
    ;;
    "aarch64")
        if [ -z "${MACHINE}" ]; then
             db_input critical ha/machine-type || true
             db_go || true
             db_get ha/machine-type || true
             MACHINE="${RET}"
             db_stop

        fi
        HASSIO_DOCKER="${DOCKER_REPO}/aarch64-hassio-supervisor"
    ;;
    *)
        error "${ARCH} unknown!"
    ;;
esac

PREFIX=${PREFIX:-/usr}
SYSCONFDIR=${SYSCONFDIR:-/etc}
DATA_SHARE=${DATA_SHARE:-$PREFIX/share/hassio}
CONFIG="${SYSCONFDIR}/hassio.json"
cat > "${CONFIG}" <<- EOF
{
    "supervisor": "${HASSIO_DOCKER}",
    "machine": "${MACHINE}",
    "data": "${DATA_SHARE}"
}
EOF

# Pull Supervisor image
info "Install supervisor Docker container"
docker pull "${HASSIO_DOCKER}:${HASSIO_VERSION}" > /dev/null
docker tag "${HASSIO_DOCKER}:${HASSIO_VERSION}" "${HASSIO_DOCKER}:latest" > /dev/null

# Install Supervisor
info "Install supervisor startup scripts"
sed -i "s,%%HASSIO_CONFIG%%,${CONFIG},g" "${PREFIX}"/sbin/hassio-supervisor
sed -i -e "s,%%BINARY_DOCKER%%,${BINARY_DOCKER},g" \
       -e "s,%%SERVICE_DOCKER%%,${SERVICE_DOCKER},g" \
       -e "s,%%BINARY_HASSIO%%,${PREFIX}/sbin/hassio-supervisor,g" \
       "${SYSCONFDIR}/systemd/system/hassio-supervisor.service"

chmod a+x "${PREFIX}/sbin/hassio-supervisor"
systemctl enable hassio-supervisor.service > /dev/null 2>&1;

# Install AppArmor
info "Install AppArmor scripts"
curl -sL ${URL_APPARMOR_PROFILE} > "${DATA_SHARE}/apparmor/hassio-supervisor"
sed -i "s,%%HASSIO_CONFIG%%,${CONFIG},g" "${PREFIX}/sbin/hassio-apparmor"
sed -i -e "s,%%SERVICE_DOCKER%%,${SERVICE_DOCKER},g" \
    -e "s,%%HASSIO_APPARMOR_BINARY%%,${PREFIX}/sbin/hassio-apparmor,g" \
    "${SYSCONFDIR}/systemd/system/hassio-apparmor.service"

chmod a+x "${PREFIX}/sbin/hassio-apparmor"
systemctl enable hassio-apparmor.service > /dev/null 2>&1;
systemctl start hassio-apparmor.service

# Start Supervisor 
info "Start Home Assistant Supervised"
systemctl start hassio-supervisor.service

# Install HA CLI
info "Installing the 'ha' cli"
chmod a+x "${PREFIX}/bin/ha"

# Switch to cgroup v1
if ! grep -q "systemd.unified_cgroup_hierarchy=false" /etc/default/grub; then
    info "Switching to cgroup v1"
    cp /etc/default/grub /etc/default/grub.bak
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&systemd.unified_cgroup_hierarchy=false /' /etc/default/grub
    update-grub
    touch /var/run/reboot-required
fi

info "Within a few minutes you will be able to reach Home Assistant at:"
info "http://homeassistant.local:8123 or using the IP address of your"
info "machine: http://${IP_ADDRESS}:8123"
if [ -f /var/run/reboot-required ]
then
    warn "A reboot is required to apply changes to grub."
fi
