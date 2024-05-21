```
TFSTATE_BUCKET=valheim-sigr-2
TFSTATE_KEY=tf-state/terraform.tfstate
TFSTATE_REGION=us-west-2

tofu init \
-backend-config="bucket=${TFSTATE_BUCKET}" \
-backend-config="key=${TFSTATE_KEY}" \
-backend-config="region=${TFSTATE_REGION}" 
```