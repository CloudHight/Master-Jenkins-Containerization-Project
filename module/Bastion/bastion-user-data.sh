# Bastion: no SSH keys are stored here. Operators connect with AWS SSM Session Manager
# (IAM role based access) or use it as an SSH ProxyJump with their own key.

# Set hostname
hostnamectl set-hostname bastion
