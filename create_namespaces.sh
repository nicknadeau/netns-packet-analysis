#!/bin/bash

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

function printUsage {
	echo "USAGE: ./$SCRIPT_NAME --num <num-ns> --prefix <host-prefix> --host-base-ip <ip> --host-subnet-mask <mask> --route-ns-name <route-ns-name>" >&2
}

function isValidIpAddress {
	if ! [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		return 1
	fi
}

function parseArgs {
	argNumIndex=-1
	argPrefixIndex=-1
	argBaseIpIndex=-1
	argSubnetMaskIndex=-1
	argRouteNameIndex=-1

	currIndex=1
	for arg in "$@"; do
		if [ "$arg" = '--num' ]; then
			argNumIndex=$((currIndex + 1))
		elif [ "$arg" = '--prefix' ]; then
			argPrefixIndex=$((currIndex + 1))
		elif [ "$arg" = '--host-base-ip' ]; then
			argBaseIpIndex=$((currIndex + 1))
		elif [ "$arg" = '--host-subnet-mask' ]; then
			argSubnetMaskIndex=$((currIndex + 1))
		elif [ "$arg" = '--route-ns-name' ]; then
			argRouteNameIndex=$((currIndex + 1))
		fi
		currIndex=$((currIndex + 1))
	done

	if [ $argNumIndex -eq -1 ]; then
		echo "Missing --num argument" >&2
		return 1
	fi
	if [ $argPrefixIndex -eq -1 ]; then
		echo "Missing --prefix argument" >&2
		return 1
	fi
	if [ $argBaseIpIndex -eq -1 ]; then
		echo "Missing --host-base-ip argument" >&2
		return 1
	fi
	if [ $argSubnetMaskIndex -eq -1 ]; then
		echo "Missing --host-subnet-mask argument" >&2
		return 1
	fi
	if [ $argRouteNameIndex -eq -1 ]; then
		echo "Missing --route-ns-name argument" >&2
		return 1
	fi

	if [ $argNumIndex -gt 10 ]; then
		echo "Missing --num value" >&2
		return 1
	fi
	if [ $argPrefixIndex -gt 10 ]; then
		echo "Missing --prefix value" >&2
		return 1
	fi
	if [ $argBaseIpIndex -gt 10 ]; then
		echo "Missing --host-base-ip value" >&2
		return 1
	fi
	if [ $argSubnetMaskIndex -gt 10 ]; then
		echo "Missing --host-subnet-mask value" >&2
		return 1
	fi
	if [ $argRouteNameIndex -gt 10 ]; then
		echo "Missing --route-ns-name value" >&2
		return 1
	fi

	ARG_NUM=${@:$argNumIndex:1}
	ARG_PREFIX=${@:$argPrefixIndex:1}
	ARG_BASE_IP=${@:$argBaseIpIndex:1}
	ARG_SUBNET_MASK=${@:$argSubnetMaskIndex:1}
	ARG_ROUTE_NAME=${@:$argRouteNameIndex:1}

	isValidIpAddress "$ARG_BASE_IP"
	if [ $? -ne 0 ]; then
		echo "Invalid IPv4 address format given: $ARG_BASE_IP" >&2
		return 1
	fi
}

function addNumToLastIpOctet {
	baseIp="$1"
	num="$2"

	lastOctet="$(echo "$baseIp" | cut -d. -f4)"
	newLastOctet=$((num + lastOctet))
	if [ $newLastOctet -gt 254 ]; then
		echo "Exceeded Ipv4 address space. Cannot assign a new ip address. Please lower the last octet in your base address or use fewer namespaces."
		return 1
	elif [ $newLastOctet -lt 2 ]; then
		echo "Cannot assign new ip address, last octect is too small a value. Please use a base address whose last octect is at least 2."
		return 1
	fi

	firstOctet="$(echo "$baseIp" | cut -d. -f1)"
	secondOctet="$(echo "$baseIp" | cut -d. -f2)"
	thirdOctet="$(echo "$baseIp" | cut -d. -f3)"
	echo "$firstOctet"."$secondOctet"."$thirdOctet"."$newLastOctet"
}

if [ $# -ne 10 ]; then
	printUsage
	exit 1
fi

parseArgs "$@"
if [ $? -ne 0 ]; then
	printUsage
	exit 1
fi

# Create the bridge device for the routing namespace and put it in promiscuous mode.
sudo ip netns add "$ARG_ROUTE_NAME" && \
	sudo ip netns exec "$ARG_ROUTE_NAME" ip link add vswitch type bridge && \
	sudo ip netns exec "$ARG_ROUTE_NAME" ip link set vswitch promisc on && \
	true
if [ $? -ne 0 ]; then
	echo "Error occurred setting up bridge device 'vswitch' in the given routing namespace: $ARG_ROUTE_NAME" >&2
	exit 1
fi

# Create the other host namespaces and their veth pairs, put them in promiscuous mode, give them an ip address, and attach them to our bridge.
for i in $(seq $ARG_NUM); do
	namespaceName="$ARG_PREFIX$i"
	vethInName="$namespaceName"_in
	vethOutName="$namespaceName"_out
	ipAddress="$(addNumToLastIpOctet "$ARG_BASE_IP" $((i - 1)))"

	sudo ip netns add "$namespaceName" && \
		sudo ip link add "$vethInName" type veth peer name "$vethOutName" && \
		sudo ip link set "$vethInName" netns "$namespaceName" && \
		sudo ip link set "$vethOutName" netns "$ARG_ROUTE_NAME" && \
		sudo ip netns exec "$namespaceName" ip link set "$vethInName" promisc on && \
		sudo ip netns exec "$ARG_ROUTE_NAME" ip link set "$vethOutName" promisc on && \
		sudo ip netns exec "$namespaceName" ip addr add "$ipAddress"/"$ARG_SUBNET_MASK" dev "$vethInName" && \
		sudo ip netns exec "$ARG_ROUTE_NAME" ip link set "$vethOutName" master vswitch && \
		true
	if [ $? -ne 0 ]; then
		echo "Error occurred setting up host namespace with veth pair for host number $i" >&2
		exit 1
	fi
done
