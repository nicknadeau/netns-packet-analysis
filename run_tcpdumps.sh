#!/bin/bash

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

function printUsage {
	echo "USAGE: ./$SCRIPT_NAME --num <num-ns> --prefix <host-prefix> --route-ns-name <route-ns-name> --dump-dir <dir> [--tcpdump-args <arg...>]" >&2
}

function parseArgs {
	argNumIndex=-1
	argPrefixIndex=-1
	argRouteNameIndex=-1
	argDumpDirIndex=-1
	argTcpdumpArgsIndex=-1

	currIndex=1
	for arg in "$@"; do
		if [ "$arg" = '--num' ]; then
			argNumIndex=$((currIndex + 1))
		elif [ "$arg" = '--prefix' ]; then
			argPrefixIndex=$((currIndex + 1))
		elif [ "$arg" = '--route-ns-name' ]; then
			argRouteNameIndex=$((currIndex + 1))
		elif [ "$arg" = '--dump-dir' ]; then
			argDumpDirIndex=$((currIndex + 1))
		elif [ "$arg" = '--tcpdump-args' ]; then
			argTcpdumpArgsIndex=$((currIndex + 1))
		fi
		currIndex=$((currIndex + 1))
	done

	# If the --tcpdump-args argument is given then it must come last. This simplifies processing a great deal and is a pretty reasonable ask.
	if [ $argTcpdumpArgsIndex -ne -1 ]; then
		if [ $argTcpdumpArgsIndex -lt $argNumIndex ] || [ $argTcpdumpArgsIndex -lt $argPrefixIndex ] || [ $argTcpdumpArgsIndex -lt $argRouteNameIndex ] || [ $argTcpdumpArgsIndex -lt $argDumpDirIndex ]; then
			echo "The --tcpdump-args argument must be the last argument supplied. Please rearrange your arguments." >&2
			return 1
		fi
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
	if [ $argDumpDirIndex -eq 1 ]; then
		echo "Missing --dump-dir argument" >&2
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
	if [ $argDumpDirIndex -gt 8 ]; then
		echo "Missing --dump-dir value" >&2
		return 1
	fi

	ARG_NUM=${@:$argNumIndex:1}
	ARG_PREFIX=${@:$argPrefixIndex:1}
	ARG_ROUTE_NAME=${@:$argRouteNameIndex:1}
	ARG_DUMP_DIR="$(realpath ${@:$argDumpDirIndex:1})"
	ARG_TCPDUMP_ARGS_INDEX=$argTcpdumpArgsIndex

	if [ ! -d "$ARG_DUMP_DIR" ]; then
		echo "Error - dump dir is not a directory"
		return 1
	fi
}


if [ $# -lt 8 ]; then
	printUsage
	exit 1
fi

parseArgs "$@"
if [ $? -ne 0 ]; then
	printUsage
	exit 1
fi

rm "$ARG_DUMP_DIR"/* &>/dev/null

# Run tcpdump in the background for the bridge and each veth pair.
# NOTE: Every tcpdump instance writes to stderr even under successful conditions. This looks confusing when running the script, because you don't get your prompt back until you press enter.
# To avoid this confusion for people using this, but also retaining the error reporting, we pipe stderr to a separate file in the dump dir.

if [ $ARG_TCPDUMP_ARGS_INDEX -ne -1 ]; then
	sudo ip netns exec "$ARG_ROUTE_NAME" tcpdump --interface vswitch ${@:$ARG_TCPDUMP_ARGS_INDEX} -s 65535 > "$ARG_DUMP_DIR"/stdout_vswitch 2>"$ARG_DUMP_DIR"/stderr_vswitch &
else
	sudo ip netns exec "$ARG_ROUTE_NAME" tcpdump --interface vswitch -s 65535 > "$ARG_DUMP_DIR"/stdout_vswitch 2>"$ARG_DUMP_DIR"/stderr_vswitch &
fi

for i in $(seq $ARG_NUM); do
	namespaceName="$ARG_PREFIX$i"
	vethInName="$namespaceName"_in
	vethOutName="$namespaceName"_out

	if [ $ARG_TCPDUMP_ARGS_INDEX -ne -1 ]; then
		sudo ip netns exec "$namespaceName" tcpdump --interface "$vethInName" ${@:$ARG_TCPDUMP_ARGS_INDEX} -s 65535 > "$ARG_DUMP_DIR"/stdout_"$vethInName" 2>"$ARG_DUMP_DIR"/stderr_"$vethInName" &
		sudo ip netns exec "$ARG_ROUTE_NAME" tcpdump --interface "$vethOutName" ${@:$ARG_TCPDUMP_ARGS_INDEX} -s 65535 > "$ARG_DUMP_DIR"/stdout_"$vethOutName" 2>"$ARG_DUMP_DIR"/stderr_"$vethOutName" &
	else
		sudo ip netns exec "$namespaceName" tcpdump --interface "$vethInName" -s 65535 > "$ARG_DUMP_DIR"/stdout_"$vethInName" 2>"$ARG_DUMP_DIR"/stderr_"$vethInName" &
		sudo ip netns exec "$ARG_ROUTE_NAME" tcpdump --interface "$vethOutName" -s 65535 > "$ARG_DUMP_DIR"/stdout_"$vethOutName" 2>"$ARG_DUMP_DIR"/stderr_"$vethOutName" &
	fi
done
