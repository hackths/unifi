#!/bin/bash
#
#<UDF name="email" label="The email address used for LetsEncrypt:">
# EMAIL=
#<UDF name="hostname" label="The hostname for the new Linode:">
# HOSTNAME=
#

# update debian
echo "Updating Debian"
apt-get update
apt-get upgrade -y
apt-get install apt-transport-https

# Setup the hostname
echo "Setting the hostname"
hostname $HOSTNAME
hostnamectl set-hostname $HOSTNAME

# Install Unifi
echo "Installing UniFi"
wget -O /etc/apt/trusted.gpg.d/unifi-repo.gpg https://dl.ubnt.com/unifi/unifi-repo.gpg 
echo 'deb http://www.ubnt.com/downloads/unifi/debian stable ubiquiti' | tee /etc/apt/sources.list.d/100-ubnt-unifi.list
apt-get update
apt-get install unifi -y

# Install LetsEncrypt
echo "Installing LetsEncrypt"
apt-get install letsencrypt -y

# Setup LetsEncrypt certificate
echo "Setting up LetsEncrypt Certificate"
wget -O /opt/gen-unifi-cert.sh https://source.sosdg.org/brielle/lets-encrypt-scripts/raw/master/gen-unifi-cert.sh
sed -i 's/--agree-tos --standalone --preferred-challenges tls-sni/--agree-tos --standalone/g' /opt/gen-unifi-cert.sh
sed -i -e '/PATH=/a\' -e 'service nginx stop' /opt/gen-unifi-cert.sh
sed -i -e "\$aservice nginx start" /opt/gen-unifi-cert.sh
chmod +x /opt/gen-unifi-cert.sh
yes no | /opt/gen-unifi-cert.sh -e $EMAIL -d $HOSTNAME

# Create crontab for LetsEncrypt
echo "Update LetsEncrypt Certificate on a schedule"
crontab -l > /tmp/letsencryptcron
echo "0 0 * * 0 /opt/gen-unifi-cert.sh -r -d $HOSTNAME" >> /tmp/letsencryptcron
crontab /tmp/letsencryptcron
rm /tmp/letsencryptcron

# Create firewall rules
echo "Creating FW Rules"
iptables -t nat -I PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 8443
iptables -A INPUT -i eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 8080 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 8443 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 8843 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
iptables -A INPUT -p udp --dport 3478 -j ACCEPT
iptables -A INPUT -j DROP
iptables -A OUTPUT -o eth0 -j ACCEPT

# Install FW persistence 
echo "Installing other Software"
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
apt-get install iptables-persistent netfilter-persistent -y

# Save firewall rules
echo "Saving FW Rules"
netfilter-persistent save

# Install Nginx
echo "Installing Nginx"
apt-get install nginx-light -y

# Configure Nginx to forward 80 to 443
echo "Configuring Nginx to forward HTTP to HTTPS"
echo "server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}" > /etc/nginx/sites-available/redirect
ln -s /etc/nginx/sites-available/redirect /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default

# Install fail2ban
echo "Installing fail2ban"
apt-get install fail2ban -y

# Restart services
echo "Restarting Services"
systemctl restart nginx
systemctl restart unifi
