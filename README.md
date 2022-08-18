# Network Namespace Packet Analysis
A simple collection of scripts that allows one to setup multiple namespaces, to simulate hosts connected to one another via a network switch, and which then turns the interfaces up, runs tcpdump, allows you to generate whatever network traffic you may wish to, and then turns the interfaces down and coalesces the various dump files into a master file with each interface on which the packet was received/transmitted labelled in the dumps, and then each line sorted temporally.

These scripts were put together to assist with some simple packet investigations that helped back some articles I've written.

These scripts were NOT designed to be generic or overly flexible. They are here to facilitate the specific types of investigation strategies outlined above, to help streamline that kind of work.

These scripts were developed on Ubuntu 18.04.6 LTS.

## Usage
### Creating Namespaces
To create `N` host namespaces (to emulate host devices on the network), run:
```shell
./create_namespace.sh --num <num-ns> --prefix <host-prefix> --host-base-ip <ip> --host-subnet-mask <mask> --route-ns-name <route-ns-name>
```
This will create namespaces named `<host-prefix>1`, `<host-prefix>2`, ..., `<prefix><num-ns>`, along with a special additional namespace named `<route-ns-name>`, which will host the network bridge device we will use to join the networks.

Example: `./create_namespaces.sh --num 3 --prefix host --route-ns-name routing --host-base-ip 10.0.1.2 --host-subnet-mask 24`

This will create the following namespaces: `host1`, `host2`, `host3`, `routing`. Inside each of the `host` namespaces will be one end of a `veth` pair and it will have ip address 10.0.1.2/24, 10.0.1.3/24, and 10.0.1.4/24 for our host namespaces 1, 2 and 3 respectively. Inside the `routing` namespace will be a bridge device named `vswitch` as well as the other ends of the `veth` pairs, connected to that bridge. The `veth` ends in the host namespaces are named `hostX_in` and the other ends are named `hostX_out`. All of the devices will be in promiscuous mode.

### Turning The Devices Up
After creating our `N` devices, we can turn them up by running (using the same arguments we supplied to the create script):
```shell
./set_devices_status.sh --status up --num <num-ns> --prefix <host-prefix> --route-ns-name <route-ns-name>
```

Example: `./set_devices_status.sh --status up --num 3 --prefix host --route-ns-name routing`

This will turn all the devices in the previous example up.

### Running Our Tcpdumps
Now that our `N` devices are created and turned up, we can launch `tcpdump` against each device. Yes, we could run just 4 instances in each namespace against the pseudo `any` device, but doing so we lose the information about which interface in particular transmitted/received the packet, which I would prefer to have. As such, this script runs one `tcpdump` instance in the background for every device we've created and will pipe its stdout to a file in a specified dump directory:
```shell
./run_tcpdumps.sh --num <num-ns> --prefix <host-prefix> --route-ns-name <route-ns-name> --dump-dir <dir> [--tcpdump-args <arg...>]
```

Example: `./run_tcpdumps.sh --num 3 --prefix host --route-ns-name routing --dump-dir ./dump`

This will spawn all the `tcpdump` instances and have them write their contents into `./dump`.

You can pass additional specific arguments into the `tcpdump` instances that are run by adding the `--tcpdump-args` argument to the end of your invocation, such as `--tcpdump-args -n -vv icmp` or whatever else is of interest to you.

NOTE: If you think something looks wrong with your dumps and there may be a problem running `tcpdump`, then inspect the `stderr_*` logs inside your dump directory for further information. These logs capture each `tcpdump`'s `stderr` stream.

### Do Something Interesting
Now that your devices are being monitored go generate some network traffic you're interested in capturing.

### Turning The Devices Down
Finally, turn the devices down. This will cause each `tcpdump` session to terminate and clean up all those background tasks. We use the same script as we used for turning the devices up, but now we set the `status` to `down`.

Example: `./set_devices_status.sh --status down --num 3 --prefix host --route-ns-name routing`

This will turn all the devices in our example down.

### Compile The Final Tcpdump
At this point, we have a collection of separate `tcpdump` output files from each of the separate instances that were running. To compile them into a single master file that displays the contents in sorted order (sorted by timestamps) run:
```shell
./compile_master_tcpdump_report.sh --num <num-ns> --prefix <host-prefix> --route-ns-name <route-ns-name> --dump-dir <dir>
```

Example: `./compile_master_tcpdump_report.sh --num 3 --prefix host --route-ns-name routing --dump-dir ./dump`

Disclaimer: This compilation script is inefficient and does not scale well with large reports. Primarily because the sorting is not as naive as running `sort`, since `tcpdump` entries can span multiple lines. A shell script is not well-suited to this sort of task. But, a shell script keeps things nice and simple, and this is meant as a demonstration and for conducting simple investigations.

### Cleaning Up
Finally, we can destroy our namespaces and clean everything up:
```shell
./destroy_namespaces.sh --num <num-ns> --prefix <host-prefix> --route-ns-name <route-ns-name>
```

Example: `./destroy_namespaces.sh --num 3 --prefix host --route-ns-name routing`

This will destroy all the namespaces we created in our example.
