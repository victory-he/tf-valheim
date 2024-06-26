#!/bin/bash

SERVER_NAME=${SERVER_NAME}
WORLD_NAME=${WORLD_NAME}
SERVER_PASS=${SERVER_PASS}
STEAM_ID=${STEAM_ID}
AWS_DEFAULT_REGION=${AWS_REGION}
S3_REGION=${S3_REGION}
EIP_ALLOC=${EIP_ALLOC}
S3_URI=${S3_URI}

# Associate allocated EIP
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/instance-id)
ASSOC_ID=$(aws ec2 describe-addresses --allocation-id=$EIP_ALLOC --query Addresses[].AssociationId --output text)
aws ec2 disassociate-address --association-id $ASSOC_ID
sleep 5
aws ec2 associate-address --instance-id $INSTANCE_ID --allocation-id $EIP_ALLOC --allow-reassociation

# Install cronie since Amazon Linux 2023 doesn't include a cron scheduler by default
yum update -y
yum install cronie wget unzip zip -y
systemctl enable crond.service
systemctl start crond.service

# Install Docker
yum install -y docker
service docker start
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose plugin
sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Create Valheim server directories
export HOME=/root
mkdir -p $HOME/valheim-server/config/backups $HOME/valheim-server/config/worlds_local $HOME/valheim-server/data $HOME/valheim-server/scripts

# Download Valheim save from S3
S3_KEY=`aws s3 --region $S3_REGION ls $S3_URI --recursive | sed "s/$WORLD_NAME\///" | sort | tail -n1 | awk '{ print $4 }'`
file_path="$HOME/valheim-server/config/worlds_local/$WORLD_NAME.db"
if [ ! -f "$file_path" ]; then
    echo "The file $file_path does not exist. Proceeding with copying from S3..."
    aws s3 --region $S3_REGION cp $S3_URI$S3_KEY $HOME/valheim-server/config/worlds_local/worlds.zip
    unzip -jo -d $HOME/valheim-server/config/worlds_local $HOME/valheim-server/config/worlds_local/worlds.zip
    rm -rf $HOME/valheim-server/config/worlds_local/$${WORLD_NAME}_* $HOME/valheim-server/config/worlds_local/worlds.zip
else
    echo "The file $file_path exists. Skipping S3 copy."
fi

# Create backup to S3 bucket script
cat > $HOME/valheim-server/scripts/s3backup.sh << EOF
#!/bin/bash
UPLOAD_BUCKET=$S3_URI
EOF
cat >> $HOME/valheim-server/scripts/s3backup.sh << 'EOF'
# Define the directory path
directory="/root/valheim-server/config/worlds_local"

# Define the backup directory path
backup_directory="/root/valheim-server/config/backups"

# Check if the directory exists
if [ -d "$directory" ]; then

    # Define the filename with timestamp
    zip_filename="worlds_$(date +"%Y%m%d-%H%M%S")"
    
    # Change into the directory to zip its contents without preserving the directory structure
    cd "$directory" || exit
    
    # Zip all contents without preserving the directory structure and output to the backup directory
    zip -j "$backup_directory/$zip_filename" *
    UPLOAD_FILE="$(ls $HOME/valheim-server/config/backups -tr | tail -1)"
    aws s3 --region us-west-2 cp $HOME/valheim-server/config/backups/$UPLOAD_FILE $UPLOAD_BUCKET
    
    # Confirmation message
    echo "Contents of directory '$directory' zipped into '$zip_filename' without preserving directory structure and saved to '$backup_directory'"
else
    echo "Error: Directory '$directory' not found."
fi
EOF
chmod +x $HOME/valheim-server/scripts/s3backup.sh

# Schedule cronjob to execute S3 bucket script every 2 hours
cat > /etc/cron.d/s3backupjob << EOF
SHELL=/bin/sh
1 */2 * * * root $HOME/valheim-server/scripts/s3backup.sh
EOF
chmod 644 /etc/cron.d/s3backupjob

# Create spot termination notice script
cat >> $HOME/valheim-server/scripts/termination-notice.sh << 'EOF'
#!/bin/bash

# Define the URL to check for termination notice   
URL="http://169.254.169.254/latest/meta-data/spot/instance-action"

# Check if the termination notice exists
RESPONSE=$(curl -s -o /dev/null -w "%%{http_code}" $URL)

if [ "$RESPONSE" -eq 200 ]; then
  echo "Termination notice received. Running upload script."
  # Run the upload script
  $HOME/valheim-server/scripts/s3backup.sh
else
  echo "No termination notice. Exiting."
fi
EOF
chmod +x $HOME/valheim-server/scripts/termination-notice.sh

(crontab -l 2>/dev/null; echo "* * * * * $HOME/valheim-server/scripts/termination-notice.sh >> /var/log/check_termination_notice.log 2>&1") | crontab -

# Install mods
mkdir -p $HOME/valheim-server/mods $HOME/valheim-server/config/bepinex/plugins
DIRECTORY="$HOME/valheim-server/mods"
cd "$DIRECTORY" || exit
wget --content-disposition https://thunderstore.io/package/download/JereKuusela/Server_devcommands/1.81.0/
wget --content-disposition https://thunderstore.io/package/download/JereKuusela/Upgrade_World/1.54.0/
wget --content-disposition https://thunderstore.io/package/download/Advize/PlantEverything/1.18.0/
wget --content-disposition https://thunderstore.io/package/download/Azumatt/AzuCraftyBoxes/1.4.0/
wget --content-disposition https://thunderstore.io/package/download/Smoothbrain/TargetPortal/1.1.19/
wget --content-disposition https://thunderstore.io/package/download/Smoothbrain/Resurrection/1.0.11/
wget --content-disposition https://thunderstore.io/package/download/Azumatt/AzuExtendedPlayerInventory/1.4.3/
wget --content-disposition https://thunderstore.io/package/download/coemt/Birds/0.1.7/

for zipfile in *.zip; do
  # Check if any zip files exist
  [ -e "$zipfile" ] || continue

  # Unzip the file with overwrite flag
  unzip -o "$zipfile"
done

mv $HOME/valheim-server/mods/*.dll $HOME/valheim-server/config/bepinex/plugins/
rm -rf $HOME/valheim-server/mods/

# Valheim container environment variables
cat > $HOME/valheim-server/valheim.env << EOF
SERVER_NAME=$SERVER_NAME
WORLD_NAME=$WORLD_NAME
SERVER_PASS=$SERVER_PASS
ADMINLIST_IDS=$STEAM_ID
SERVER_PUBLIC=true
SERVER_PORT=2456
SERVER_PUBLIC=true
RESTART_CRON=0 10 * * *
BEPINEX=true
EOF
curl -o $HOME/valheim-server/docker-compose.yaml https://raw.githubusercontent.com/lloesche/valheim-server-docker/main/docker-compose.yaml
cd $HOME/valheim-server
docker-compose up
