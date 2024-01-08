#!/bin/bash

# Valheim envs
export HOME=/root
SERVER_NAME=${SERVER_NAME}
WORLD_NAME=${WORLD_NAME}
SERVER_PASS=${SERVER_PASS}
STEAM_ID=${STEAM_ID}

# AWS envs
AWS_DEFAULT_REGION=${AWS_REGION}
S3_REGION=${S3_REGION}
EIP_ALLOC=${EIP_ALLOC}
S3_URI=${S3_URI}
S3_KEY=`aws s3 --region $S3_REGION ls $S3_URI --recursive | sed "s/$WORLD_NAME\///" | sort | tail -n1 | awk '{ print $4 }'`

# Associate allocated EIP
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/instance-id)
ASSOC_ID=$(aws ec2 describe-addresses --allocation-id=$EIP_ALLOC --query Addresses[].AssociationId --output text)
aws ec2 disassociate-address --association-id $ASSOC_ID
sleep 5
aws ec2 associate-address --instance-id $INSTANCE_ID --allocation-id $EIP_ALLOC --allow-reassociation

# Install cronie since Amazon Linux 2023 doesn't include a cron scheduler by default
yum update -y
yum install cronie -y
systemctl enable crond.service
systemctl start crond.service

# Install Docker
yum install -y docker
service docker start
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose plugin
DOCKER_CONFIG=$${DOCKER_CONFIG:-$HOME/.docker}
echo $DOCKER_CONFIG > $HOME/valheim-server/escape.txt
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.23.3/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

# Create Valheim server directories
mkdir -p $HOME/valheim-server/config/backups $HOME/valheim-server/config/worlds_local $HOME/valheim-server/data $HOME/valheim-server/scripts

# Create backup to S3 bucket script
cat > $HOME/valheim-server/scripts/s3backup.sh << EOF
UPLOAD_BUCKET=$S3_URI
EOF
cat >> $HOME/valheim-server/scripts/s3backup.sh << 'EOF'
UPLOAD_FILE="$(ls $HOME/valheim-server/config/backups -tr | tail -1)"
aws s3 --region us-west-2 cp $HOME/valheim-server/config/backups/$UPLOAD_FILE $UPLOAD_BUCKET/
EOF
chmod +x $HOME/valheim-server/scripts/s3backup.sh

# Schedule cronjob to execute S3 bucket script every 2 hours
cat > /etc/cron.d/s3backupjob << EOF
SHELL=/bin/sh
1 */2 * * * root $HOME/valheim-server/scripts/s3backup.sh
EOF
chmod 644 /etc/cron.d/s3backupjob

# Download initial Valheim save and cleanup
aws s3 --region $S3_REGION cp $S3_URI/$S3_KEY $HOME/valheim-server/config/worlds_local/worlds.zip
unzip -jo -d $HOME/valheim-server/config/worlds_local $HOME/valheim-server/config/worlds_local/worlds.zip
# Clean up backup files
rm -rf $HOME/valheim-server/config/worlds_local/$${WORLD_NAME}_* $HOME/valheim-server/config/worlds_local/worlds.zip

cat > $HOME/valheim-server/valheim.env << EOF
SERVER_NAME=$SERVER_NAME
WORLD_NAME=$WORLD_NAME
SERVER_PASS=$SERVER_PASS
ADMINLIST_IDS=$STEAM_ID
SERVER_PUBLIC=true
SERVER_PORT=2456
SERVER_PUBLIC=true
RESTART_CRON=0 10 * * *
EOF
curl -o $HOME/valheim-server/docker-compose.yaml https://raw.githubusercontent.com/lloesche/valheim-server-docker/main/docker-compose.yaml
cd $HOME/valheim-server
docker compose up
