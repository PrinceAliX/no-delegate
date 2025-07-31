#!/bin/bash

# Colors
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
CYAN=$(tput setaf 6)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)

# Defaults
SCOPES="https://www.googleapis.com/auth/cloud-platform"
AUDIENCE="https://example.com"
MESSAGE="deadbeef"

# Help function
usage() {
  echo "Usage: $0 -token <access_token_file> -file <service_account_list>"
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -token)
      TOKEN_FILE="$2"
      shift; shift
      ;;
    -file)
      SERVICE_ACCOUNTS_FILE="$2"
      shift; shift
      ;;
    *)
      echo "${RED}❌ Unknown argument: $1${RESET}"
      usage
      ;;
  esac
done

# Check required arguments
if [[ -z "$TOKEN_FILE" || -z "$SERVICE_ACCOUNTS_FILE" ]]; then
  echo "${RED}❌ Missing required arguments.${RESET}"
  usage
fi

# Read token
if [[ ! -f "$TOKEN_FILE" ]]; then
  echo "${RED}❌ Token file not found: $TOKEN_FILE${RESET}"
  exit 1
fi
ACCESS_TOKEN=$(cat "$TOKEN_FILE")

# Main loop
while read -r SA; do
  echo -e "\n${CYAN}===================================="
  echo "TARGET SERVICE ACCOUNT: $SA"
  echo -e "====================================${RESET}"

  IAT=$(date +%s)
  EXP=$((IAT + 3600))

  #### ----------- signJwt -----------
  echo -n "[*] signJwt... "
  CLAIMS=$(jq -cn \
    --arg iss "$SA" \
    --arg scope "$SCOPES" \
    --arg aud "https://oauth2.googleapis.com/token" \
    --argjson iat "$IAT" \
    --argjson exp "$EXP" \
    '{iss:$iss,scope:$scope,aud:$aud,iat:$iat,exp:$exp}')
  REQ=$(jq -cn --arg payload "$CLAIMS" '{payload:$payload}')
  RESP=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
               -H "Content-Type: application/json" \
               -X POST --data "$REQ" \
               "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/$SA:signJwt")
  if echo "$RESP" | jq -e '.signedJwt' > /dev/null 2>&1; then
    echo -e "${GREEN}✅ success${RESET}"
    echo "$RESP" | jq -r '.signedJwt'
  else
    MSG=$(echo "$RESP" | jq -r '.error.message // "Unknown error"')
    echo -e "${RED}❌ $MSG${RESET}"
  fi

  #### ----------- signBlob -----------
  echo -n "[*] signBlob... "
  REQ=$(jq -cn --arg payload "$MESSAGE" '{payload:$payload}')
  RESP=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
               -H "Content-Type: application/json" \
               -X POST --data "$REQ" \
               "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/$SA:signBlob")
  if echo "$RESP" | jq -e '.signedBlob' > /dev/null 2>&1; then
    echo -e "${GREEN}✅ success${RESET}"
    echo "$RESP" | jq -r '.signedBlob'
  else
    MSG=$(echo "$RESP" | jq -r '.error.message // "Unknown error"')
    echo -e "${RED}❌ $MSG${RESET}"
  fi

  #### ----------- generateAccessToken -----------
  echo -n "[*] generateAccessToken... "
  REQ=$(jq -cn --argjson scopes "[\"$SCOPES\"]" '{scope:$scopes}')
  RESP=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
               -H "Content-Type: application/json" \
               -X POST --data "$REQ" \
               "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/$SA:generateAccessToken")
  if echo "$RESP" | jq -e '.accessToken' > /dev/null 2>&1; then
    echo -e "${GREEN}✅ success${RESET}"
    echo "$RESP" | jq
  else
    MSG=$(echo "$RESP" | jq -r '.error.message // "Unknown error"')
    echo -e "${RED}❌ $MSG${RESET}"
  fi

  #### ----------- generateIdToken -----------
  echo -n "[*] generateIdToken... "
  REQ=$(jq -cn --arg aud "$AUDIENCE" '{audience:$aud,includeEmail:true}')
  RESP=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
               -H "Content-Type: application/json" \
               -X POST --data "$REQ" \
               "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/$SA:generateIdToken")
  if echo "$RESP" | jq -e '.token' > /dev/null 2>&1; then
    echo -e "${GREEN}✅ success${RESET}"
    echo "$RESP" | jq
  else
    MSG=$(echo "$RESP" | jq -r '.error.message // "Unknown error"')
    echo -e "${RED}❌ $MSG${RESET}"
  fi

done < "$SERVICE_ACCOUNTS_FILE"
