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
