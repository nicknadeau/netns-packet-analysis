#!/bin/bash

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

function printUsage {
	echo "USAGE: ./$SCRIPT_NAME --num <num-ns> --prefix <host-prefix> --route-ns-name <route-ns-name> --dump-dir <dir>" >&2
}

function parseArgs {
	argNumIndex=-1
	argPrefixIndex=-1
	argRouteNameIndex=-1
	argDumpDirIndex=-1

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

	if [ ! -d "$ARG_DUMP_DIR" ]; then
		echo "Error - dump dir is not a directory"
		return 1
	fi
}

function injectDeviceNameIntoTcpdumpLine {
	targetFile="$(realpath "$1")"
	dstFile="$(realpath "$2")"
	deviceName="$3"

	# If the line begins with a timestamp then it is the start of a new entry. We inject our device name after that timestamp. 
	# Otherwise, do not augment the line, it is part of an entry which begins on a prior line.
	while IFS= read -r line; do
		if [[ "$line" =~ ^[0-9]+:[0-9]+:[0-9]+\.[0-9]+ ]]; then
			lineTimestamp="$(echo $line | awk '{print $1}')"
			lineRemainder="$(echo "$line" | sed 's/[^ ]* *//')"
			echo "$lineTimestamp $deviceName $lineRemainder" >> "$dstFile"
		else
			echo "$line" >> "$dstFile"
		fi
	done < "$targetFile"

	# It the file was empty, then we touch the destination file just so it exists.
	if [ "$(cat "$targetFile" | wc -l)" -eq 0 ]; then
		touch "$dstFile"
	fi
}

function saveAllTimestampLineNumsSorted {
	# We need to get all the timestamps in the file, since those mark the start of each entry, and then sort those.
	# From there, looking at this sorted ordering, we need to find the line numbers of each entry, so that we know where each entry begins, in the prior sorted order.
	targetFile="$(realpath "$1")"
	dstFile="$(realpath "$2")"

	savedAtLeastOneLine=false
	for timestamp in $(cat "$targetFile" | grep -E '^[0-9]+:[0-9]+:[0-9]+.[0-9]+' |  awk '{print $1}' | sort); do
		echo "$(cat "$targetFile" | grep -n "$timestamp" | cut -f1 -d:)" >> "$dstFile"
		savedAtLeastOneLine=true
	done

	# If we didn't save any lines then all our reports must be empty. We just touch an empty destination file then, so that subsequent functions can work as intended.
	if ! $savedAtLeastOneLine; then
		touch "$dstFile"
	fi
}

function writeAllEntriesSorted {
	# We need to read each of the sorted entry line numbers in one by one and then write that line and all subseuqent lines until we hit the start of another entry or EOF.
	# This strategy will sort multi-line entries without accidentally sorting the interior of each line.
	targetFile="$(realpath "$1")"
	dstFile="$(realpath "$2")"
	sortedLinesFile="$(realpath "$3")"

	numLinesTotal="$(cat "$targetFile" | wc -l)"
	while IFS= read -r lineNum; do
		# Write the starting line of the entry.
		cat "$targetFile" | sed -n "$lineNum"p >> "$dstFile"

		# Write any remaining lines for this entry.
		currLineNum=$lineNum
		doneWritingEntry=false
		while ! $doneWritingEntry; do
			currLineNum=$((currLineNum + 1))
			grep -x -q "$currLineNum" "$sortedLinesFile"
			if [ $? -eq 0 ]; then
				doneWritingEntry=true
			else
				if [ $currLineNum -gt $numLinesTotal ]; then
					doneWritingEntry=true
				else
					cat "$targetFile" | sed -n "$currLineNum"p >> "$dstFile"
				fi
			fi
		done
	done < "$sortedLinesFile"

	# If the total number of lines in the file is zero then we have an empty master report. We just touch an empty file so that the user can see this.
	if [ $numLinesTotal -eq 0 ]; then
		touch "$dstFile"
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

rm "$ARG_DUMP_DIR"/*.tmp &>/dev/null
rm "$ARG_DUMP_DIR/tcpdump_master_dump" &>/dev/null

# Iterate over each stdout tcpdump file and inject the device name into each line of it.
for file in $(find "$ARG_DUMP_DIR" -name '*'); do
	fileBasename="$(basename "$file")"
	if [ -f "$file" ] && [[ "$fileBasename" =~ ^stdout_.* ]]; then
		fileDir="$(dirname "$file")"
		interface="$(echo "$fileBasename" | cut -c 8-)"
		injectDeviceNameIntoTcpdumpLine "$file" "$fileDir/$fileBasename.tmp" "$interface"
		cat "$fileDir/$fileBasename.tmp" >> "$fileDir/raw_master.tmp"
	fi
done

saveAllTimestampLineNumsSorted "$fileDir/raw_master.tmp" "$fileDir/raw_master_timestamps.tmp" && \
	writeAllEntriesSorted "$fileDir/raw_master.tmp" "$fileDir/tcpdump_master_dump" "$fileDir/raw_master_timestamps.tmp" && \
	rm "$ARG_DUMP_DIR"/*.tmp && \
	true
if [ $? -eq 0 ]; then
	echo "Master report successfully written to: $fileDir/tcpdump_master_dump"
else
	echo "Error occurred writing master file" >&2
	exit 1
fi
