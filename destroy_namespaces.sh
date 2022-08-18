#!/bin/bash

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

function printUsage {
	echo "USAGE: ./$SCRIPT_NAME --num <num-ns> --prefix <host-prefix> --route-ns-name <route-ns-name>" >&2
}

function parseArgs {
	argNumIndex=-1
	argPrefixIndex=-1
	argRouteNameIndex=-1

	currIndex=1
	for arg in "$@"; do
		if [ "$arg" = '--num' ]; then
			argNumIndex=$((currIndex + 1))
		elif [ "$arg" = '--prefix' ]; then
			argPrefixIndex=$((currIndex + 1))
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
	if [ $argRouteNameIndex -eq -1 ]; then
		echo "Missing --route-ns-name argument" >&2
		return 1
	fi

	if [ $argNumIndex -gt 6 ]; then
		echo "Missing --num value" >&2
		return 1
	fi
	if [ $argPrefixIndex -gt 6 ]; then
		echo "Missing --prefix value" >&2
		return 1
	fi
	if [ $argRouteNameIndex -gt 6 ]; then
		echo "Missing --route-ns-name value" >&2
		return 1
	fi

	ARG_NUM=${@:$argNumIndex:1}
	ARG_PREFIX=${@:$argPrefixIndex:1}
	ARG_ROUTE_NAME=${@:$argRouteNameIndex:1}
}

if [ $# -ne 6 ]; then
	printUsage
	exit 1
fi

parseArgs "$@"
if [ $? -ne 0 ]; then
	printUsage
	exit 1
fi


sudo ip netns del "$ARG_ROUTE_NAME"

for i in $(seq $ARG_NUM); do
	namespaceName="$ARG_PREFIX$i"
	sudo ip netns del "$namespaceName"
done
