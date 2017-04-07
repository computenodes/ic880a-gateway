#! /bin/bash

cd /opt/ttn-gateway/bin
# Reset iC880a PIN
./reset_iC880.sh
RESTART_LIMIT=3
RESET_LIMIT=2
# Test the connection, wait if needed.
while [[ $(ping -c1 google.com 2>&1 | grep " 0% packet loss") == "" ]]; do
  echo "[TTN Gateway]: Waiting for internet connection..."
  sleep 30
  done

# If there's a remote config, try to update it
if [ -d ../gateway-remote-config ]; then
    # First pull from the repo
    pushd ../gateway-remote-config/
    git pull
    git reset --hard
    popd

    # And then try to refresh the gateway EUI and re-link local_conf.json

    # Same eth0/wlan0 fallback as on install.sh
    GATEWAY_EUI_NIC="eth0"
    if [[ `grep "$GATEWAY_EUI_NIC" /proc/net/dev` == "" ]]; then
        GATEWAY_EUI_NIC="wlan0"
    fi

    if [[ `grep "$GATEWAY_EUI_NIC" /proc/net/dev` == "" ]]; then
        echo "ERROR: No network interface found. Cannot set gateway ID."
        exit 1
    fi

    GATEWAY_EUI=$(ip link show $GATEWAY_EUI_NIC | awk '/ether/ {print $2}' | awk -F\: '{print $1$2$3"FFFE"$4$5$6}')
    GATEWAY_EUI=`echo ${GATEWAY_EUI} | tr [a-z] [A-Z]` # toupper

    echo "[TTN Gateway]: Use Gateway EUI $GATEWAY_EUI based on $GATEWAY_EUI_NIC"
    INSTALL_DIR="/opt/ttn-gateway"
    LOCAL_CONFIG_FILE=$INSTALL_DIR/bin/local_conf.json

    if [ -e $LOCAL_CONFIG_FILE ]; then rm $LOCAL_CONFIG_FILE; fi;
    ln -s $INSTALL_DIR/gateway-remote-config/$GATEWAY_EUI.json $LOCAL_CONFIG_FILE

fi

RESTART_COUNT=0 #number of times a restart without a reset tried
RESET_COUNT=0
while [ $RESET_COUNT -lt $RESET_LIMIT ]; do
   while [ $RESTART_COUNT -lt $RESTART_LIMIT ]; do
	# Fire up the forwarder.
        ./poly_pkt_fwd
        if  [ $? == 0 ]; then #we exited happily therefore end the script
    	    echo "Poly packet forward exited cleanly"
            exit 0 
        fi
	>&2 echo "Unclean exit trying again (${RESTART_COUNT}/${RESTART_LIMIT})"
	let RESTART_COUNT=RESTART_COUNT+1
    done
    ./reset_iC880.sh
    let RESET_COUNT=RESET_COUNT+1
    let RESTART_COUNT=0 ##reset restart counter
    >&2 echo "Unclean exit resetting and trying again (${RESET_COUNT}/${RESET_LIMIT})"
done
        
