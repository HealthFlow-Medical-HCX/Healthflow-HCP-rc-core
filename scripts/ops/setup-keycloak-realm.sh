#!/bin/bash
set -euo pipefail
KC=http://localhost:8080
ADMIN_PW=$(grep -oP 'KEYCLOAK_ADMIN_PASSWORD=\K.*' /opt/healthflow/docker/.env)

token() {
  curl -s -d "client_id=admin-cli" -d "username=admin" -d "password=$ADMIN_PW" \
    -d "grant_type=password" "$KC/realms/master/protocol/openid-connect/token" \
    | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])"
}
T=$(token)

# 1) Create healthflow realm (idempotent)
EXISTS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $T" "$KC/admin/realms/healthflow")
if [ "$EXISTS" = "200" ]; then
  echo "realm 'healthflow' already exists"
else
  curl -s -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
    "$KC/admin/realms" -d '{
      "realm": "healthflow",
      "enabled": true,
      "displayName": "HealthFlow HCP Registry",
      "sslRequired": "external",
      "registrationAllowed": false,
      "loginWithEmailAllowed": true,
      "duplicateEmailsAllowed": false,
      "resetPasswordAllowed": true,
      "accessTokenLifespan": 1800
    }'
  echo "created realm 'healthflow'"
fi

# 2) Create a confidential client 'registry' for the Sunbird-RC registry (idempotent)
T=$(token)
CID=$(curl -s -H "Authorization: Bearer $T" "$KC/admin/realms/healthflow/clients?clientId=registry" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d[0]['id'] if d else '')")
if [ -n "$CID" ]; then
  echo "client 'registry' already exists ($CID)"
else
  curl -s -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
    "$KC/admin/realms/healthflow/clients" -d '{
      "clientId": "registry",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "serviceAccountsEnabled": true,
      "directAccessGrantsEnabled": true,
      "standardFlowEnabled": true,
      "redirectUris": ["https://registry.healthflow.eg/*","http://146.190.204.129:8081/*"],
      "webOrigins": ["*"]
    }'
  echo "created client 'registry'"
fi

# 3) Create realm roles commonly used by HCP registry (idempotent)
T=$(token)
for ROLE in admin issuer verifier provider; do
  ex=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $T" "$KC/admin/realms/healthflow/roles/$ROLE")
  if [ "$ex" = "200" ]; then echo "role $ROLE exists";
  else curl -s -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
        "$KC/admin/realms/healthflow/roles" -d "{\"name\":\"$ROLE\"}"; echo "created role $ROLE"; fi
done

echo "=== final realm list ==="
T=$(token)
curl -s -H "Authorization: Bearer $T" "$KC/admin/realms" \
  | python3 -c "import sys,json;[print('realm:',r['realm'],'enabled:',r['enabled']) for r in json.load(sys.stdin)]"
echo "KEYCLOAK_REALM_SETUP_DONE"
