#!/usr/bin/env bash
##
# tgardiner: Base AMI
##
set -ex
export DEBIAN_FRONTEND=noninteractive

# Update and upgrade
apt-get -yq update && apt-get -yq upgrade

# Install basic services & utilities
apt-get -yq install rsyslog awscli

# Download amazon-cloudwatch-agent
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb.sig

# Check file checksum and signature
gpg --import amazon-cloudwatch-agent.gpg
if ! gpg --verify amazon-cloudwatch-agent.deb.sig amazon-cloudwatch-agent.deb; then
  echo Invalid file checksum and/or signature
  exit 1
fi

# Install amazon-cloudwatch-agent
dpkg -i -E ./amazon-cloudwatch-agent.deb

# Start amazon-cloudwatch-agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s -c file:amazon-cloudwatch-agent.json

# Install ssh keys
wget -q -O /home/ubuntu/.ssh/authorized_keys https://github.com/tgardiner.keys
