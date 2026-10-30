locals {
  ansible_userdata = join("\n", [
    "#!/bin/bash",
    "set -e",
    "AWS_REGION=${var.region}",
    "CW_CONFIG_PARAM=${var.cw_config_param}",
    # 2 GB swap: dnf on RHEL loads large repo metadata and can exhaust RAM and stall the boot
    "if [ ! -f /swapfile ]; then dd if=/dev/zero of=/swapfile bs=1M count=2048 && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi",
    # SSM agent first (RHEL AMIs don't ship it): Jenkins deploys run ansible-playbook here through
    # SSM Run Command, and it gives shell access to debug the rest of this script if a step fails
    "rpm -q amazon-ssm-agent || rpm -ivh https://s3.${var.region}.amazonaws.com/amazon-ssm-${var.region}/latest/linux_amd64/amazon-ssm-agent.rpm",
    "systemctl enable --now amazon-ssm-agent",
    file("${path.module}/../common/bootstrap.sh"),
    local.ansible_setup,
  ])

  ansible_setup = <<-EOF
# -------------------------------
# 1️⃣ Update system & install dependencies
# -------------------------------
sudo yum update -y
sudo yum install -y wget unzip git

# -------------------------------
# 2️⃣ Install Ansible
# -------------------------------
sudo dnf install -y ansible-core

# -------------------------------
# 3️⃣ Configure SSH for Ansible (key read from AWS Secrets Manager)
# -------------------------------
sudo mkdir -p /home/ec2-user/.ssh
get_secret "${var.ssh_key_secret_arn}" | sudo tee /home/ec2-user/.ssh/id_rsa > /dev/null
sudo chmod 400 /home/ec2-user/.ssh/id_rsa
sudo chown ec2-user:ec2-user /home/ec2-user/.ssh/id_rsa

# Disable strict host key checking for ec2-user
sudo tee -a /home/ec2-user/.ssh/config > /dev/null <<EOF2
Host *
  StrictHostKeyChecking no
EOF2
sudo chmod 600 /home/ec2-user/.ssh/config
sudo chown ec2-user:ec2-user /home/ec2-user/.ssh/config

# -------------------------------
# 4️⃣ Pull Ansible scripts from S3
# -------------------------------
sudo mkdir -p /home/ec2-user/ansible
sudo aws s3 cp s3://${aws_s3_bucket.ansible-scripts.id}/ansible-script/prod-bashscript.sh /home/ec2-user/ansible/prod-bashscript.sh
sudo aws s3 cp s3://${aws_s3_bucket.ansible-scripts.id}/ansible-script/stage-bashscript.sh /home/ec2-user/ansible/stage-bashscript.sh
sudo aws s3 cp s3://${aws_s3_bucket.ansible-scripts.id}/ansible-script/deployment.yml /home/ec2-user/ansible/deployment.yml

# Set permissions
sudo chmod 755 /home/ec2-user/ansible/*.sh
sudo chown -R ec2-user:ec2-user /home/ec2-user/ansible

# -------------------------------
# 5️⃣ Create Ansible variable file (no secrets - the hosts read them from Secrets Manager)
# -------------------------------
sudo tee /home/ec2-user/ansible/ansible_vars_file.yml > /dev/null <<EOF2
NEXUS_REGISTRY: ${var.nexus_registry}
NEXUS_SECRET_ID: ${var.nexus_secret_arn}
AWS_REGION: ${var.region}
EOF2
sudo chown ec2-user:ec2-user /home/ec2-user/ansible/ansible_vars_file.yml
sudo chmod 644 /home/ec2-user/ansible/ansible_vars_file.yml

# -------------------------------
# 6️⃣ Configure cron jobs for scripts
# -------------------------------
sudo crontab -u ec2-user -l > /tmp/mycron || true
echo "* * * * * sh /home/ec2-user/ansible/prod-bashscript.sh" >> /tmp/mycron
echo "* * * * * sh /home/ec2-user/ansible/stage-bashscript.sh" >> /tmp/mycron
sudo crontab -u ec2-user /tmp/mycron
rm -f /tmp/mycron

# -------------------------------
# 7️⃣ Set hostname
# -------------------------------
sudo hostnamectl set-hostname ansible-server

EOF
}
