# Follow along this tutorial to recreate an exercise seen in class

For this second TP we need to connect PC1 - which is a device not connected to a network - to PC3 - a device well within the network - through PC2 which acts as a router.

We will be replicating this environment in Docker by creating 3 separate containers. 

This is the image we will be using, it is Ubuntu like the devices at the University and also has all of the tools we will need in the `Tools` section. 
It also **disables and stops the NetworkManager** as done at the beginning of our TPs and does **port forwarding**.

## Dockerfile

```dockerfile
# School devices
FROM ubuntu:22.04 

# Set non-interactive mode for package installation
ENV DEBIAN_FRONTEND=noninteractive

# Tools
RUN apt-get update && apt-get install -y \
    iproute2 \        
    iputils-ping \    
    net-tools \      
    iptables \        
    tcpdump \        
    nano \            
    && apt-get clean

# some of these are just ChatGPT recommendations, and won't be used, they exist only for optional debugging, which I won't cover because I don't make mistakes.

  
# Disable NetworkManager to prevent interference with manual network configuration
RUN systemctl disable NetworkManager && systemctl stop NetworkManager || true

# Allows IPv4 forwarding by default in all containers
RUN echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && sysctl -p

# Command to keep the container running for this exercise, we can go into it using docker exec -it <container_name> /bin/bash
CMD ["tail", "-f", "/dev/null"]
```


In our project we will build the image that w will make containers from and we will call it a device since every container we make will act as one.

```docker
docker build -t device .
```

## Container creation

Now we make our 3 containers PC1, PC2 and PC3. Which will be the disconnected device, the router device and the destination device respectively.

```docker
docker run -d --name PC1 --privileged  device
```

the ``privileged``option is to allow us to manage interna systems in the container, such as routing.


Before doing anything this is what the `docker inspect PC1` looks like
```dockerfile

"NetworkSettings": {
            "Bridge": "",
            "Gateway": "172.17.0.1", # IMPORTANT
            "IPAddress": "172.17.0.2", # IMPORTANT
            "MacAddress": "02:42:ac:11:00:02", # IMPORTANT
            "Networks": {
                "bridge": {
                    "MacAddress": "02:42:ac:11:00:02", # IMPORTANT
                    "Gateway": "172.17.0.1", # IMPORTANT
                    "IPAddress": "172.17.0.2", # IMPORTANT
                }
            }
        }
```

Here we can see that the containers - because they are at the moment all the same - are connected to the bridge network, which is a default and predefined network given by docker itself.

Obviously we need to change this, so we will create 2 networks, one will be an actual network in our exercise and the other will be our Ethernet connection.


## Docker networks

Here we will create the networks needed for this exercise, now there is a small catch and that it that we don't have Ethernet cables in Docker, however we will simulate that with a smaller subnet and just say it is an Ethernet connection. It won't change anything in this project.

```docker
docker network create --subnet=192.168.1.0/24 ethernet_connection
docker network create --subnet=10.192.0.0/16 actual_network_connection
```

Now that we have these two networks available, we will connect via docker PC2 and PC3 to the `actual_network_connection` and then we will manually assign a route in PC2 that connects to the `ethernet_connection` network. 

In PC1 we will add a default gateway, which will be the **PC2 interface's IP address** because we are trying to send a ping to an unknown device - and thus it needs to ``exit the network`` and ``hop`` to the next.

In PC3 we will also add a **default gateway** which will be the **2nd interface on PC2**, to properly send things back when we don't know where they came from - as it happens, the initial ping doesn't know where it is going, it is exploratory.

Which means that the entire process will go like this :

PC1 sends a ping to the PC3's IP - which is an address in the `actual_network_connection`. This ping will obviously not be in this initial network, the `ethernet_connection` and thus will be sent out the ``default gateway`` - which means PC2 'collects' the ping and forwards the packet.

Now that the ping is being forwarded by PC2 and, since PC2 can 'see' this network because of it's routing table, we can safely say that the packet will be sent properly to PC3 from PC1. 

This is great but now we need to also have the way back to think about, so we need to make the ``default gateway of PC3`` be the **other PC2 interface's IP address** so that the packet finds its way back to an environment in which PC1 is visible - PC2.

### Commands to run

Still we need to connect both PC2 and PC3 to the ``actual_network_connection``
```docker
docker network connect actual_network_connection PC2
docker network connect actual_network_connection PC3
```

This is what the edited inspect for one of the containers should look like
```docker
"Networks": {
	"actual_network_connection": {
		"MacAddress": "02:42:0a:c0:00:02",
		"Gateway": "10.192.0.1",
		"IPAddress": "10.192.0.2",
		"DNSNames": [
			"PC2",
			"a5a5ca9bb225"
		]
	}, ...
```

Here can see that it has now it's own IP address in the network -  `10.192.0.2` and that the default gateway is - ``10.192.0.1``.

However we can't see interfaces here, which is slightly problematic for our exercise since we know that PC2 has 2 interfaces - that can be the same type such as  eno1 and ten again eno1 - with 2 different IP addresses.

After entering the docker container and running the ``ifconfig`` command we can now see the different interfaces in PC2.

```terminal
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 172.17.0.3  netmask 255.255.0.0  broadcast 172.17.255.255
        ether 02:42:ac:11:00:03  txqueuelen 0  (Ethernet)
        RX packets 7  bytes 746 (746.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

eth1: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 10.192.0.2  netmask 255.255.0.0  broadcast 10.192.255.255
        ether 02:42:0a:c0:00:02  txqueuelen 0  (Ethernet)
        RX packets 14  bytes 1572 (1.5 KB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
```

Here are the 2 interfaces on PC2, `eth0` is for the connections to the internet - the outer network, which in this case is generated by docker. And then we have the `eth1` which is the interface connected to the `actual_network_connection`. 

On PC3 it is the same, the only difference being the different IP addresses of the interfaces : being `eth0` - **172.17.0.4** and `eth1` - **10.192.0.3**.


### What the routing tables look like here

#### PC3
This is the routing table  - product of the `ip route show` command on the PC3 device. 

---
**default via 10.192.0.1 dev eth1** 
10.192.0.0/16 dev eth1 proto kernel scope link src 10.192.0.3
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.4

---
Which says that if it doesn't find the correct IP address to send a packet to, send it to **10.192.0.1** over the `eth1` interface.

#### PC2
This is the routing table for PC2

---
**default via 10.192.0.1 dev eth1**
10.192.0.0/16 dev eth1 proto kernel scope link src 10.192.0.2
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.3 

---
Which specifies - at the moment - the same place as PC3. Which we don't want.


This is what the edited inspect for the `actual_network_connection` should look like
```docker
[
    {
        "Name": "actual_network_connection",
            "Config": [
                {
                    "Subnet": "10.192.0.0/16"
                }
            ],
        "Containers": {
                "Name": "PC3",
                "MacAddress": "02:42:0a:c0:00:03",
                "IPv4Address": "10.192.0.3/16",
            },
                "Name": "PC2",
                "MacAddress": "02:42:0a:c0:00:02",
                "IPv4Address": "10.192.0.2/16",
            }
        }
]
```

Now we also need to connect 2 devices to the `ethernet_connection` PC1 and PC2

```docker
docker network connect ethernet_connection PC1
docker network connect ethernet_connection PC2
```

---
# Interlude

So now we have both of our networks, our `actual_network_connection` and our `ethernet_connection`. And we have the correct devices connected to them - done with the docker connect command. 

We now can ping from PC2 to PC3, and from PC1 to PC2. We need to set up routes to allow PC1 to ping PC3. 

As of right now you cannot, and should not be able to ping from PC1, the IP of PC3.

---
## Setting up routes

Now we will set up the default gateway of PC1 to be PC2's interface's IP. And then in PC3 set the default to be PC2's other interface's IP.


If done in the same order, the same interfaces on your machine and in my example will be the same.

**PC1**
```terminal
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 172.17.0.2  netmask 255.255.0.0  broadcast 172.17.255.255
        ether 02:42:ac:11:00:02  txqueuelen 0  (Ethernet)

eth1: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 192.168.1.2  netmask 255.255.255.0  broadcast 192.168.1.255        
        ether 02:42:c0:a8:01:02  txqueuelen 0  (Ethernet)
```

`eth0` - Interface that connects to the 'Internet', which is a default network provided by docker.
`eth1` - Interface for the `ethernet_connection`

**PC2**
```terminal
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 172.17.0.3  netmask 255.255.0.0  broadcast 172.17.255.255
        ether 02:42:ac:11:00:03  txqueuelen 0  (Ethernet)

eth1: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 10.192.0.2  netmask 255.255.0.0  broadcast 10.192.255.255
        ether 02:42:0a:c0:00:02  txqueuelen 0  (Ethernet)

eth2: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 192.168.1.3  netmask 255.255.255.0  broadcast 192.168.1.255        
        ether 02:42:c0:a8:01:03  txqueuelen 0  (Ethernet)
```

`eth0` - Docker / Internet interface
`eth1` - Interface to `actual_network_connection`
`eth2` - Interface to `ethernet_connection`

**PC3**
```terminal
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 172.17.0.4  netmask 255.255.0.0  broadcast 172.17.255.255
        ether 02:42:ac:11:00:04  txqueuelen 0  (Ethernet)

eth1: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 10.192.0.3  netmask 255.255.0.0  broadcast 10.192.255.255
        ether 02:42:0a:c0:00:03  txqueuelen 0  (Ethernet)
```

`eth0` - Docker / Internet interface
`eth1` - Interface to `actual_network_connection`


Now we need to set up the routes, which are just the default gateways in this case to make this system work.

First default gateway is from PC1 to PC2.

#### In PC1

Note :  you may need to delete the default one, you most likely will
```routing commands
// first command is to delete the default gateway
ip route del default

// this command adds the default
ip route add default gateway 192.168.1.3 via eth1
```

 
Routing table after 

---
**default via 192.168.1.3 dev eth1**
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.2   
192.168.1.0/24 dev eth1 proto kernel scope link src 192.168.1.2 

---

The next one is from PC3 back to PC2.

#### In PC3

```routing commands
ip route del default // have to delete the old one
ip route add default gateway 10.192.0.2 via eth1
```


Routing table after

---
**default via 10.192.0.2 dev eth1** 
10.192.0.0/16 dev eth1 proto kernel scope link src 10.192.0.3
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.4

---

# Final check

Now since you have properly added routes to your containers you should be able to make a ping from PC1 - **192.168.1.2** - to the IP at PC3 - **10.192.0.3** -

Let's check . . . Works!
