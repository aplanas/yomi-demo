# yomi-demo

Small script to bootstrap a demonstration for [Yomi](https://github.com/openSUSE/yomi).

The script will download the ISO image with the minion, will install
(inside a Python virtual environment) the last salt-master, will
configure the service and download the Yomi code.

After that the script will create two pillars, designed to install
openSUSE Tumbleweed and MicroOS in two different kind of nodes:

* Node 1: BIOS machine, with a single HD (MicroOS).
* Node 2: UEFI machine, with two HDs with LVM (Tumbleweed).

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
# Run the script in background. It will download the assents
./run.sh -c &

# From the Grub command line, add master=10.0.2.2 to the kernel
# command line

# Activate the new venv (wait until the VMs are up)
source venv/bin/activate

# Testing the environment. We ping all the VMs
salt -c venv/etc/salt '*' test.ping

# Install openSUSE in node 1 (BIOS & MicroOS)
salt -c venv/etc/salt '00:00:00:11:11:11' state.highstate

# Install openSUSE in node 2 (EFI & Tumbleweed & LVM)
salt -c venv/etc/salt '00:00:00:22:22:22' state.highstate

# Install openSUSE in both nodes at the same time
salt -c venv/etc/salt '*' state.highstate
```

Note that in order that the `salt-minion` can find the `salt-master`
service, we need to add `master=10.0.2.2` in the kernel command line
from the Grub boot loader. If we miss this step, we can add it later:

```Bash
echo "master: 10.0.2.2" > /etc/salt/minion.d/master.conf
```

In a different terminal we can monitor the installation using the Yomi
monitoring tool.

```Bash
source venv/bin/activate

export SALTAPI_URL=http://localhost:8000
export SALTAPI_EAUTH=file
export SALTAPI_USER=salt
export SALTAPI_PASS=linux

srv/monitor -r -y
```

You can add the user and password directly to the `monitor` call:

```Bash
source venv/bin/activate
srv/monitor -u http://localhost:8000 -a file -n salt -p linux -r -y
```

Now, in the first terminal, we can launch the installation in all the
nodes:

```Bash
salt -c venv/etc/salt '*' state.highstate
```

# Troubleshooting

Several elements can go wrong with the demo, lets see some of them:

* Salt-master start slow

  A bug reported shows that in some environment (for example, when
  ybind is used), makes `salt-master` start slow. This can cause
  problems with `salt-api` later or. A simple solution is to make sure
  that both services are down and start them manually: first
  `salt-master`, and once is up, `salt-api`. Check the code to see how
  to do that properly.

* The software state fails

  If there is a problem with the openSUSE repositories, this state can
  fail. This will not abort the installation (failhard is not set in
  the minions), so this will produce a chain of fails later on. A
  solution is to set a local repo, or wait a bit until the openSUSE
  repositories are working again.
  
* The monitor tool fails the authentication

  For speed purposes the monitor cache the authentication tokens
  locally. The parameter `-r` remove this cache, as I can expect that
  the environment will be recreated and the services will be restarted
  (something that invalidate the tokens). If the `monitor` fails to
  authenticate, double check that the `-r` parameter is in place.

* The monitor tools shows error in mount / umount states

  If you are commenting the `kexec` state in `installer.sls`, Yomi
  will not umount the chroot environment. This is done on to simplify
  the debugging, and also `kexec` needs this accessible to find the
  kernel. In that case a second run on Yomi will show errors in the
  mount / umount states. Is safe to ignore them.
