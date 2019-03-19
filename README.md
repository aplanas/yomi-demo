# yomi-demo

Small script to bootstrap a demonstration for [Yomi](https://github.com/openSUSE/yomi).

The script will download the ISO image with the minion, will install
(inside a Python virtual environment) the last salt-master, will
configure the service and download the Yomi code.

After that the script will create two pillars, designed to install
openSUSE Tumbleweed in two different kind of nodes:

* Node 1: BIOS machine, with a single HD.
* Node 2: UEFI machine, with two HDs with LVM.

After that it will restart the `salt-master` service and launch two
QEMU nodes, that match those profiles.

Together with `salt-master`, an instance of `salt-api` will be
launched and listening to port 8000. This will be the connector for
the monitor.

The `auth` module of `salt-api` will be configured to read the user
and password from a file, in `venv/etc/user-list.txt`. For this demo
the user will be `salt` and the password `linux`. This file will be
reset to those values every time the script is executed.

To remove all the downloaded assets and re-download it, we can run the
script with the `-f` parameter. If we want only to recreate the QCOW2
images (for example, to generate another run on Yomi), we can use the
`-c` parameter. Use `-h` to check the help options.

```Bash
# Run the script in background. I will download the assents
./run.sh -c &

# Activate the new venv (wait until the VMs are up)
source venv/bin/activate

# Testing the environment. We ping all the VMs
salt -c venv/etc/salt '*' test.ping

# Install openSUSE in node 1
salt -c venv/etc/salt '00:00:00:11:11:11' state.highstate

# Install openSUSE in node 2
salt -c venv/etc/salt '00:00:00:22:22:22' state.highstate

# Install openSUSE in both nodes at the same time
salt -c venv/etc/salt '*' state.highstate
```

In a different terminal we can monitor the installation using the Yomi
monitoring tool.

```Bash
source venv/bin/activate

export SALTAPI_URL=http://localhost:8000
export SALTAPI_EAUTH=file
export SALTAPI_USER=salt
export SALTAPI_PASS=linux

srv/monitor -r -e
```

You can add the user and password directly to the `monitor` call:

```Bash
source venv/bin/activate
srv/monitor -u http://localhost:8000 -a file -n salt -p linux -r -e
```

Now, in the first terminal, we can launch the installation in all the
nodes:

```Bash
salt -c venv/etc/salt '*' state.highstate
```
