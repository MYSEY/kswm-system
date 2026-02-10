#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

echo "🧪 Testing .env file loading..."
echo "📁 Project root: $PROJECT_ROOT"
echo "📄 .env file: $ENV_FILE"
echo ""

if [ ! -f "$ENV_FILE" ]; then
    echo "❌ .env file not found!"
    exit 1
fi

# Load AWS configuration from .env
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_DEFAULT_REGION=""
AWS_BUCKET=""
AWS_ENDPOINT=""
AWS_URL=""

while IFS='=' read -r key value; do
    [[ $key =~ ^[[:space:]]*# ]] && continue
    [[ -z $key ]] && continue
    
    value=$(echo "$value" | sed 's/^["'"'"']//' | sed 's/["'"'"']$//')
    
    case $key in
        AWS_ACCESS_KEY_ID) AWS_ACCESS_KEY_ID="$value" ;;
        AWS_SECRET_ACCESS_KEY) AWS_SECRET_ACCESS_KEY="$value" ;;
        AWS_DEFAULT_REGION) AWS_DEFAULT_REGION="$value" ;;
        AWS_BUCKET) AWS_BUCKET="$value" ;;
        AWS_ENDPOINT) AWS_ENDPOINT="$value" ;;
        AWS_URL) AWS_URL="$value" ;;
    esac
done < "$ENV_FILE"

echo "📋 Loaded configuration:"
echo "  Access Key: ${AWS_ACCESS_KEY_ID:0:8}..."
echo "  Secret Key: ${AWS_SECRET_ACCESS_KEY:0:8}..."
echo "  Region: $AWS_DEFAULT_REGION"
echo "  Bucket: $AWS_BUCKET"
echo "  Endpoint: $AWS_ENDPOINT"
echo "  URL: $AWS_URL"
echo ""

# Test s3cmd with loaded config
echo "🔧 Testing s3cmd configuration..."

temp_config="/tmp/test_s3cfg"
cat > "$temp_config" << EOF
[default]
access_key = $AWS_ACCESS_KEY_ID
secret_key = $AWS_SECRET_ACCESS_KEY
host_base = $(echo "$AWS_ENDPOINT" | sed 's|https://||')
host_bucket = %(bucket)s.$(echo "$AWS_ENDPOINT" | sed 's|https://||')
bucket_location = $AWS_DEFAULT_REGION
use_https = True
signature_v2 = False
EOF

echo "📄 Generated s3cmd config:"
cat "$temp_config"
echo ""

echo "🌐 Testing connection..."
if s3cmd -c "$temp_config" ls "s3://$AWS_BUCKET" > /dev/null 2>&1; then
    echo "✅ Connection successful!"
    echo "📁 Files in bucket:"
    s3cmd -c "$temp_config" ls "s3://$AWS_BUCKET" | head -5
else
    echo "❌ Connection failed!"
fi

rm -f "$temp_config"
echo ""
echo "🎉 Test completed!"