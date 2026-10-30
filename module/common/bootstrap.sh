# ---------------------------------------------------------------------------
# Common bootstrap (prepended to every server's user data)
# Expects: AWS_REGION, CW_CONFIG_PARAM
# Installs AWS CLI v2 + CloudWatch agent and loads the agent config from SSM
# ---------------------------------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y unzip curl
  curl -fsSL -o /tmp/amazon-cloudwatch-agent.deb https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
  dpkg -i -E /tmp/amazon-cloudwatch-agent.deb
else
  dnf install -y unzip
  dnf install -y https://amazoncloudwatch-agent.s3.amazonaws.com/redhat/amd64/latest/amazon-cloudwatch-agent.rpm
fi

if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL -o /tmp/awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
  unzip -q -o /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install --update
  ln -sf /usr/local/bin/aws /usr/bin/aws
  rm -rf /tmp/awscliv2.zip /tmp/aws
fi

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c "ssm:${CW_CONFIG_PARAM}"

# Read a secret value from AWS Secrets Manager (uses the instance role)
get_secret() {
  aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$1" --query SecretString --output text
}
