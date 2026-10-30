#!/bin/bash

set -e  # stop on error

# Update system
sudo yum update -y

# Install base dependencies
sudo yum install -y wget git python3-pip maven unzip yum-utils

# Install SSM Agent (FIXED - removed region issue)
sudo yum install -y https://s3.amazonaws.com/amazon-ssm-us-east-1/latest/linux_amd64/amazon-ssm-agent.rpm

# Install Session Manager Plugin (FIXED)
curl -o session-manager-plugin.rpm https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm
sudo yum install -y session-manager-plugin.rpm

# Install Amazon Corretto 21 (ensure Java 21 is the system default)
sudo curl -L -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo
sudo yum install -y java-21-amazon-corretto-devel
# Ensure alternatives and JAVA_HOME point to Corretto 21
if [ -d "/usr/lib/jvm/java-21-amazon-corretto" ]; then
	sudo alternatives --set java /usr/lib/jvm/java-21-amazon-corretto/bin/java || true
	echo 'JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto' | sudo tee /etc/profile.d/java.sh
	sudo chmod +x /etc/profile.d/java.sh
	source /etc/profile.d/java.sh || true
fi

# Add Jenkins repo
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo

# Import Jenkins key
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

# Install Jenkins
sudo yum install -y jenkins

# Ensure Jenkins uses Corretto 21
echo 'JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto' | sudo tee /etc/sysconfig/jenkins
sudo systemctl daemon-reexec
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Install Docker dependencies
sudo yum install -y device-mapper-persistent-data lvm2

# Add Docker repo
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Install Docker
sudo yum install -y docker-ce docker-ce-cli containerd.io

# Start Docker
sudo systemctl enable docker
sudo systemctl start docker

# Add users to Docker group
sudo usermod -aG docker ec2-user
sudo usermod -aG docker jenkins

# Fix Docker socket permissions
sudo chmod 666 /var/run/docker.sock

# Install Trivy
cat <<EOF | sudo tee /etc/yum.repos.d/trivy.repo
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/7/\$basearch/
gpgcheck=0
enabled=1
EOF

sudo yum install -y trivy

# Set hostname
sudo hostnamectl set-hostname jenkins

echo "✅ Installation complete!"