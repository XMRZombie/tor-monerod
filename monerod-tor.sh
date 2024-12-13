#!/bin/bash

# Default directories and files
DIR="."
MONEROD_CONF="$DIR/monerod-conf/bitmonerod.conf"
TORDIR="$DIR/tor-conf"
TORRC="$TORDIR/torrc"
HOSTNAMEFILE="$TORDIR/hostname"
MONEROD=$(find "$DIR" -type f -name "monerod" -executable 2>/dev/null)

# Function to print usage/help
usage() {
    echo "Usage: $0 [--config | --run]"
    echo "  --config  Generate configuration files for Tor and monerod"
    echo "  --run     Generate configuration files and start monerod and Tor"
    exit 1
}

# Parse command-line arguments
if [[ $# -lt 1 ]]; then
    usage
fi

ACTION=$1

# Check if monerod executable was found
if [[ -z "$MONEROD" ]]; then
    echo "monerod executable not found!"
    exit 1
fi

# Function to create directories if they don't exist
create_directories() {
    mkdir -p "$DIR/monerod-conf"
    mkdir -p "$TORDIR"
    chmod 700 "$TORDIR"
}

# Function to create configuration files (only if they don't exist)
create_config() {
    create_directories

    if [[ ! -f "$TORRC" || ! -f "$MONEROD_CONF" ]]; then
        echo "Creating Tor configuration..."
        rm -f "$TORRC"

        # Create torrc file
        cat << EOF > "$TORRC"
ControlSocket $TORDIR/control
ControlSocketsGroupWritable 1
CookieAuthentication 1
CookieAuthFile $TORDIR/control.authcookie
CookieAuthFileGroupReadable 1
SocksPort 9050 IsolateDestAddr
SocksPort 9052 OnionTrafficOnly IsolateDestAddr
HiddenServiceDir $TORDIR
HiddenServicePort 18083 127.0.0.1:18083
HiddenServiceEnableIntroDoSDefense 1
HiddenServiceEnableIntroDoSRatePerSec 10
HiddenServiceEnableIntroDoSBurstPerSec 20
HiddenServicePoWDefensesEnabled 1
HiddenServicePoWQueueRate 5
HiddenServicePoWQueueBurst 10
HiddenServiceMaxStreams 1000
HiddenServiceMaxStreamsCloseCircuit 1
EOF

        echo "Tor configuration generated at $TORRC"
        
        # Now set up monerod configuration
        echo "Configuring monerod"
        HOSTNAME=""
        if [[ -f "$HOSTNAMEFILE" ]]; then
            HOSTNAME=$(cat "$HOSTNAMEFILE")
        fi

        if [[ -z "$HOSTNAME" ]]; then
            echo "Error: Tor hostname not found!"
            exit 1
        fi

        cat << EOF > "$MONEROD_CONF"
anonymous-inbound="$HOSTNAME":18083,127.0.0.1:18083,25
proxy=127.0.0.1:9050
tx-proxy=tor,127.0.0.1:9052,10
add-priority-node=zbjkbsxc5munw3qusl7j2hpcmikhqocdf4pqhnhtpzw5nt5jrmofptid.onion:18083
EOF

        echo "Monero configuration generated at $MONEROD_CONF"
    else
        echo "Configuration files already exist. Skipping configuration generation."
    fi
}

# Function to run the services (Tor and monerod)
run_services() {

    echo "Starting Tor..."
    nohup tor -f "$TORRC" 2> "$TORDIR/tor.stderr" 1> "$TORDIR/tor.stdout" &

    # Wait for Tor to start and the hostname file to appear
    ready=0
    for i in $(seq 10); do
        sleep 1
        if [[ -f "$HOSTNAMEFILE" ]]; then
            ready=1
            break
        fi
    done

    if [[ $ready -eq 0 ]]; then
        echo "Error starting Tor"
        cat "$TORDIR/tor.stdout"
        exit 1
    fi

    HOSTNAME=$(cat "$HOSTNAMEFILE")
    echo "Tor started. Hidden service hostname: $HOSTNAME"

    echo "Starting monerod..."
    "$MONEROD" --conf "$MONEROD_CONF" --detach

    # Wait for monerod to start and check its status
    ready=0
    for i in $(seq 10); do
        sleep 1
        status=$("$MONEROD" status)
        echo "$status" | grep -q "Height:"
        if [[ $? -eq 0 ]]; then
            ready=1
            break
        fi
    done

    if [[ $ready -eq 0 ]]; then
        echo "Error starting monerod"
        tail -n 400 "$HOME/.bitmonero/bitmonero.log" | grep -Ev "stacktrace|Error: Couldn't connect to daemon:|src/daemon/main.cpp:.*Monero" | tail -n 20
        exit 1
    fi

    echo "Monerod is ready. Tor hidden service hostname: $HOSTNAME"
}

# Run the corresponding action
case $ACTION in
    --config)
        create_config
        ;;
    --run)
        run_services
        ;;
    *)
        usage
        ;;
esac
