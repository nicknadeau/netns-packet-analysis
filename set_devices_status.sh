#!/bin/bash

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

function printUsage {
	echo "USAGE: ./$SCRIPT_NAME --status <'up'|'down'> --num <num-ns> --prefix <host-prefix> --route-ns-name <route-ns-name>" >&2
}

function parseArgs {
	argStatusIndex=-1
	argNumIndex=-1
	argPrefixIndex=-1
	argRouteNameIndex=-1

	currIndex=1
	for arg in "$@"; do
		if [ "$arg" = '--status' ]; then
			argStatusIndex=$((currIndex + 1))
		elif [ "$arg" = '--num' ]; then
			argNumIndex=$((currIndex + 1))
		elif [ "$arg" = '--prefix' ]; then
			argPrefixIndex=$((currIndex + 1))
		elif [ "$arg" = '--route-ns-name' ]; then
			argRouteNameIndex=$((currIndex + 1))
		fi
		currIndex=$((currIndex + 1))
	done

	if [ $argStatusIndex -eq -1 ]; then
		echo "Missing --status argument" >&2
		return 1
	fi
	if [ $argNumIndex -eq -1 ]; then
		echo "Missing --num argument" >&2
		return 1
	fi
	if [ $argPrefixIndex -eq -1 ]; then
		echo "Missing --prefix argument" >&2
		return 1
	fi
	if [ $argRouteNameIndex -eq -1 ]; then
		echo "Missing --route-ns-name argument" >&2
		return 1
	fi

	if [ $argStatusIndex -gt 8 ]; then
		echo "Missing --status value" >&2
		return 1
	fi
	if [ $argNumIndex -gt 8 ]; then
		echo "Missing --num value" >&2
		return 1
	fi
	if [ $argPrefixIndex -gt 8 ]; then
		echo "Missing --prefix value" >&2
		return 1
	fi
	if [ $argRouteNameIndex -gt 8 ]; then
		echo "Missing --route-ns-name value" >&2
		return 1
	fi

	ARG_STATUS=${@:$argStatusIndex:1}
	ARG_NUM=${@:$argNumIndex:1}
	ARG_PREFIX=${@:$argPrefixIndex:1}
	ARG_ROUTE_NAME=${@:$argRouteNameIndex:1}

	if [ "$ARG_STATUS" != 'up' ] && [ "$ARG_STATUS" != 'down' ]; then
		echo "Invalid --status value. Must be one of: up, down" >&2
		return 1
	fi
}

if [ $# -ne 8 ]; then
	printUsage
	exit 1
fi

parseArgs "$@"
if [ $? -ne 0 ]; then
	printUsage
	exit 1
fi

# Turn all the veth devices up.
for i in $(seq $ARG_NUM); do
	namespaceName="$ARG_PREFIX$i"
	vethInName="$namespaceName"_in
	vethOutName="$namespaceName"_out

	sudo ip netns exec "$namespaceName" ip link set dev "$vethInName" "$ARG_STATUS" && \
		sudo ip netns exec "$ARG_ROUTE_NAME" ip link set dev "$vethOutName" "$ARG_STATUS" && \
		true
	if [ $? -ne 0 ]; then
		echo "Error occurred turning veth pairs up" >&2
		exit 1
	fi
done

# Turn the bridge up.
sudo ip netns exec "$ARG_ROUTE_NAME" ip link set dev vswitch "$ARG_STATUS"
