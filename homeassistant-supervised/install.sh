#!/usr/bin/env bash

set -e

function info { echo -e "\e[32m[info] $*\e[39m"; }
function warn  { echo -e "\e[33m[warn] $*\e[39m"; }
function error { echo -e "\e[31m[error] $*\e[39m"; exit 1; }

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

systemctl enable apparmor.service
systemctl start apparmor.service

mkdir -p /etc/dbus-1/system.d
cp -f ./etc/dbus-1/system.d/io.hass.conf /etc/dbus-1/system.d/io.hass.conf
cp -f ./etc/docker/daemon.json /etc/docker/daemon.json
cp -f ./etc/NetworkManager/system-connections/default /etc/NetworkManager/system-connections/default
cp -f ./etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf
cp -f ./etc/systemd/system/haos-agent.service /etc/systemd/system/haos-agent.service
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
URL_VERSION="https://${URL_VERSION_HOST}/stable.json"
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

OS_AGENT_VERSION="$(curl -s https://api.github.com/repos/home-assistant/os-agent/releases/latest | jq -r .name)"

case ${ARCH} in
    "i386" | "i686")
        MACHINE=${MACHINE:=qemux86}
        HASSIO_DOCKER="${DOCKER_REPO}/i386-hassio-supervisor"
        OSAGENT_URL="https://github.com/home-assistant/os-agent/releases/download/${OS_AGENT_VERSION}/os-agent_${OS_AGENT_VERSION}_linux_i386.deb"
    ;;
    "x86_64")
        MACHINE=${MACHINE:=qemux86-64}
        HASSIO_DOCKER="${DOCKER_REPO}/amd64-hassio-supervisor"
        OSAGENT_URL="https://github.com/home-assistant/os-agent/releases/download/${OS_AGENT_VERSION}/os-agent_${OS_AGENT_VERSION}_linux_x86_64.deb"
    ;;
    "arm" |"armv6l")
        select mach in generic-x86-64 odroid-c2 odroid-n2 odroid-xu qemuarm qemuarm-64 qemux86 qemux86-64 raspberrypi raspberrypi2 raspberrypi3 raspberrypi4 raspberrypi3-64 raspberrypi4-64 tinker khadas-vim3
        do
            MACHINE="${mach}"
            break
        done
        HASSIO_DOCKER="${DOCKER_REPO}/armhf-hassio-supervisor"
        OSAGENT_URL="https://github.com/home-assistant/os-agent/releases/download/${OS_AGENT_VERSION}/os-agent_${OS_AGENT_VERSION}_linux_armv5.deb"
    ;;
    "armv7l")
        select mach in generic-x86-64 odroid-c2 odroid-n2 odroid-xu qemuarm qemuarm-64 qemux86 qemux86-64 raspberrypi raspberrypi2 raspberrypi3 raspberrypi4 raspberrypi3-64 raspberrypi4-64 tinker khadas-vim3
        do
            MACHINE="${mach}"
            break
        done
        HASSIO_DOCKER="${DOCKER_REPO}/armv7-hassio-supervisor"
        OSAGENT_URL="https://github.com/home-assistant/os-agent/releases/download/${OS_AGENT_VERSION}/os-agent_${OS_AGENT_VERSION}_linux_armv7.deb"
    ;;
    "aarch64")
        select mach in generic-x86-64 odroid-c2 odroid-n2 odroid-xu qemuarm qemuarm-64 qemux86 qemux86-64 raspberrypi raspberrypi2 raspberrypi3 raspberrypi4 raspberrypi3-64 raspberrypi4-64 tinker khadas-vim3
        do
            MACHINE="${mach}"
            break
        done
        MACHINE="raspberrypi4-64"
        HASSIO_DOCKER="${DOCKER_REPO}/aarch64-hassio-supervisor"
        OSAGENT_URL="https://github.com/home-assistant/os-agent/releases/download/${OS_AGENT_VERSION}/os-agent_${OS_AGENT_VERSION}_linux_aarch64.deb"
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

systemctl daemon-reload

# Install os-agent
WORKDIR=$(mktemp -d -t hass-workdir.XXXXXXXXXX)
cd ${WORKDIR}
curl -fsSL "${OSAGENT_URL}" -o osagent.deb
ar x osagent.deb
tar -xvf data.tar.gz
cp -f ./usr/bin/os-agent /usr/bin/os-agent
cd -
rm -rf ${WORKDIR}
chmod a+x "/usr/bin/os-agent"
systemctl enable haos-agent.service > /dev/null 2>&1;
systemctl start haos-agent.service

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

info "Within a few minutes you will be able to reach Home Assistant at:"
info "http://homeassistant.local:8123 or using the IP address of your"
info "machine: http://${IP_ADDRESS}:8123"
