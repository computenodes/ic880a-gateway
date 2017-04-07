#!/bin/bash

# Stop on the first sign of trouble
set -e

if [ $UID != 0 ]; then
    echo "ERROR: Operation not permitted. Forgot sudo?"
    exit 1
fi

VERSION="spi"
if [[ $1 != "" ]]; then VERSION=$1; fi

echo "The Things Network Gateway installer (ALPINE)"
echo "Version $VERSION"

# Update the gateway installer to the correct branch
echo "Updating installer files..."
OLD_HEAD=$(git rev-parse HEAD)
#git fetch
#git checkout -q $VERSION
#git pull
NEW_HEAD=$(git rev-parse HEAD)

if [[ $OLD_HEAD != $NEW_HEAD ]]; then
    echo "New installer found. Restarting process..."
    exec "./install.sh" "$VERSION"
fi

# Request gateway configuration data
# There are two ways to do it, manually specify everything
# or rely on the gateway EUI and retrieve settings files from remote (recommended)
echo "Gateway configuration:"

GATEWAY_EUI_NIC=eth0
if [[ `grep "$GATEWAY_EUI_NIC" /proc/net/dev` == "" ]]; then
    GATEWAY_EUI_NIC="wlan0"
fi

if [[ `grep "$GATEWAY_EUI_NIC" /proc/net/dev` == "" ]]; then
    echo "ERROR: No network interface found.  Cannot set gateway ID."
    exit 1
fi

GATEWAY_EUI=$(ip link show $GATEWAY_EUI_NIC | awk '/ether/ {print $2}' | awk -F\: '{print $1$2$3"FFFE"$4$5$6}')
GATEWAY_EUI=`echo ${GATEWAY_EUI} | tr [a-z] [A-Z]` # toupper

echo "Detected EUI $GATEWAY_EUI from $GATEWAY_EUI_NIC"

read -r -p "Do you want to use remote settings file? [y/N]" response
response=`echo ${response}| tr [A-Z][a-z]` # tolower

if echo $response| grep -E "^(yes|y)"; then
    REMOTE_CONFIG=true
else
    DEFAULT_GATEWAY_NAME=$(hostname)
    printf "       Descriptive name [${DEFAULT_GATEWAY_NAME}]:"
    read GATEWAY_NAME
    if echo $GATEWAY_NAME | grep -E "^$"; then GATEWAY_NAME=${DEFAULT_GATEWAY_NAME}; fi
    printf "       Contact email: "
    read GATEWAY_EMAIL

    printf "       Latitude [0]: "
    read GATEWAY_LAT
    if echo $GATEWAY_LAT | grep -E "^$"; then GATEWAY_LAT=0; fi

    printf "       Longitude [0]: "
    read GATEWAY_LON
    if echo $GATEWAY_LON | grep -E "^$"; then GATEWAY_LON=0; fi

    printf "       Altitude [0]: "
    read GATEWAY_ALT
    if echo $GATEWAY_ALT | grep -E "^$"; then GATEWAY_ALT=0; fi
fi


# remove hostname changing
CURRENT_HOSTNAME=$(hostname)
echo "Installing Deps..."
apk add alpine-sdk linux-headers


# Install LoRaWAN packet forwarder repositories
INSTALL_DIR="/opt/ttn-gateway"
if [ ! -d "$INSTALL_DIR" ]; then mkdir -p $INSTALL_DIR; fi
SETUP_DIR=`pwd`
cd $INSTALL_DIR

# Build LoRa gateway app
if [ ! -d lora_gateway ]; then
    git clone https://github.com/pjb304/lora_gateway.git
    cd lora_gateway
else
    cd lora_gateway
    git reset --hard
    git pull
fi

sed -i -e 's/PLATFORM= kerlink/PLATFORM= imst_rpi/g' ./libloragw/library.cfg

make

cd $INSTALL_DIR

# Build packet forwarder
if [ ! -d packet_forwarder ]; then
    git clone https://github.com/pjb304/packet_forwarder.git
    cd packet_forwarder
else
    cd packet_forwarder
    git pull
    git reset --hard
fi

make

cd $INSTALL_DIR

# Symlink poly packet forwarder
if [ ! -d bin ]; then mkdir bin; fi
if [ -f ./bin/poly_pkt_fwd ]; then rm ./bin/poly_pkt_fwd; fi
ln -s $INSTALL_DIR/packet_forwarder/poly_pkt_fwd/poly_pkt_fwd ./bin/poly_pkt_fwd
cp -f ./packet_forwarder/poly_pkt_fwd/global_conf.json ./bin/global_conf.json

LOCAL_CONFIG_FILE=$INSTALL_DIR/bin/local_conf.json

# Remove old config file - it's an actual file
if [ -f $LOCAL_CONFIG_FILE ]; then rm $LOCAL_CONFIG_FILE; fi;
#remove old symlink to config file
if [ -L $LOCAL_CONFIG_FILE ]; then unlink $LOCAL_CONFIG_FILE; fi;

if [ "$REMOTE_CONFIG" = true ] ; then
    # Get remote configuration repo
    if [ ! -d gateway-remote-config ]; then
        git clone https://github.com/pjb304/gateway-remote-config.git
        cd gateway-remote-config
    else
        cd gateway-remote-config
        git pull
        git reset --hard
    fi

    ln -s $INSTALL_DIR/gateway-remote-config/$GATEWAY_EUI.json $LOCAL_CONFIG_FILE

    cd $INSTALL_DIR
else
    echo -e "{\n\t\"gateway_conf\": {\n\t\t\"gateway_ID\": \"$GATEWAY_EUI\",\n\t\t\"servers\": [ { \"server_address\": \"router.eu.thethings.network\", \"serv_port_up\": 1700, \"serv_port_down\": 1700, \"serv_enabled\": true } ],\n\t\t\"ref_latitude\": $GATEWAY_LAT,\n\t\t\"ref_longitude\": $GATEWAY_LON,\n\t\t\"ref_altitude\": $GATEWAY_ALT,\n\t\t\"contact_email\": \"$GATEWAY_EMAIL\",\n\t\t\"description\": \"$GATEWAY_NAME\" \n\t}\n}" >$LOCAL_CONFIG_FILE
fi

cd $INSTALL_DIR

echo "Gateway EUI is: $GATEWAY_EUI"
echo "The hostname is: $(hostname)"
echo "Check gateway status here (find your EUI): http://staging.thethingsnetwork.org/gatewaystatus/"
echo
echo "Installation completed."
cd $SETUP_DIR
# Start packet forwarder as a service
cp ./start.sh $INSTALL_DIR/bin/
cp ./reset_iC880.sh $INSTALL_DIR/bin

cp ttn_gateway /etc/init.d
#cp ./ttn-gateway.service /lib/systemd/system/

