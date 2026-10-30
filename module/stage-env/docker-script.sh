#!/bin/bash

#updatng the instance
sudo yum update -y
sudo yum upgrade -y

#install Docker and its dependencies, start Docker service
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo #downloads & adds repo to instance
sudo yum install docker-ce -y

#Starts the Docker service and enables it to run on boot.
sudo systemctl start docker
sudo systemctl enable docker

#add the ec2-user to the docker group, allowing them to run Docker commands.
sudo usermod -aG docker ec2-user

#create a shell script that manages a Docker container on the EC2 instance, pulling updates from a Nexus registry
#i.e. Configure docker to fetch image from Nexus (over TLS via the Nexus ALB)
sudo mkdir -p /home/ec2-user/scripts
cat << EOF > "/home/ec2-user/scripts/script.sh"
#!/bin/bash

set -x

#Define Variables
NEXUS_REGISTRY="${nexus_registry}"
IMAGE_NAME="${nexus_registry}/petclinicapps"
CONTAINER_NAME="appContainer"

#Function to login to Nexus (password read from AWS Secrets Manager via the instance role)
authenticate_docker() {
    aws secretsmanager get-secret-value --region ${region} --secret-id ${nexus_secret_id} --query SecretString --output text \
      | docker login --username admin --password-stdin \$NEXUS_REGISTRY
}

#Function to check for latest image on Nexus
check_for_updates() {
    local latest_image=\$(docker pull \$IMAGE_NAME | grep "Status: Image is up to date" | wc -l)
    if [ \$latest_image -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

#Function to stop and remove the current container
#Function to deploy image in a container
update_container() {
  docker stop \$CONTAINER_NAME
  docker rm \$CONTAINER_NAME
  docker run -d --name \$CONTAINER_NAME -p 8080:8080 \$IMAGE_NAME
}

#Main Function
main() {
    authenticate_docker
    if check_for_updates; then
        update_container
        echo "Container upgraded to latest image."
    else
        echo "Up to date! No image update required. Exiting..."
    fi
}
main
EOF

sudo chown -R ec2-user:ec2-user /home/ec2-user/scripts
sudo chmod 750 /home/ec2-user/scripts/script.sh

#setting the host name
sudo hostnamectl set-hostname stage-instance
sudo reboot
