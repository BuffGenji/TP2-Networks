# Use a lightweight Linux base image
FROM ubuntu:22.04

# Set non-interactive mode for package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update and install required tools
RUN apt-get update && apt-get install -y \
    iproute2 \        
    iputils-ping \    
    net-tools \       
    iptables \        
    tcpdump \         
    nano \            
    && apt-get clean

# Disable NetworkManager to prevent interference with manual network configuration
RUN systemctl disable NetworkManager && systemctl stop NetworkManager || true

# Allow IPv4 forwarding by default
RUN echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && sysctl -p

# command to keep the container running for this exercise, we can go into it using docker exec -it
CMD ["tail", "-f", "/dev/null"]