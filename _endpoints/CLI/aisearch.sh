#!/usr/bin/env bash

# Executes the Microsoft Foundry connection migration one operation at a time.
# Authenticate first with: az login --use-device-code
# When multiple subscriptions are available, this script selects SUBID explicitly.

set -Eeuo pipefail

# Azure resource configuration. These values are not secrets.
SUBID="eca2eddb-0f0c-4351-a634-52751499eeea"
RESOURCE_GROUP="rg-aifoundry7159"
FOUNDRY_ACCOUNT="foundry7159"
PROJECT_NAME="aif7159-standard-agent-project"
SEARCH_SERVICE_NAME="CHANGE_ME"

# Microsoft Foundry project resource configuration.
CAPABILITY_HOST_NAME="projectCapabilityHost"
OLD_SEARCH_CONNECTION_NAME="mysearch-conn"
NEW_SEARCH_CONNECTION_NAME="mysearch-conn-v2"
STORAGE_CONNECTION_NAME="mystorage-conn"
COSMOS_CONNECTION_NAME="mycosmos-conn"
CAPABILITY_HOSTS_API_VERSION="2026-05-01"
CONNECTIONS_API_VERSION="2026-05-01"

MANAGEMENT_ENDPOINT="https://management.azure.com"
PROJECT_RESOURCE_PATH="/subscriptions/${SUBID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT}/projects/${PROJECT_NAME}"
SEARCH_RESOURCE_ID="/subscriptions/${SUBID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Search/searchServices/${SEARCH_SERVICE_NAME}"

# Verifies Azure CLI authentication and selects the configured subscription.
initialize_azure_context() {
    command -v az >/dev/null 2>&1 || {
        echo "ERROR: Azure CLI is not installed or is not available in PATH." >&2
        return 1
    }

    az account show --output none >/dev/null 2>&1 || {
        echo "ERROR: Sign in first with 'az login --use-device-code'." >&2
        return 1
    }

    az account set --subscription "$SUBID"
    echo "Using subscription: $(az account show --query name --output tsv) ($SUBID)"
}

# Stops execution when the Azure AI Search service name is still a placeholder.
validate_configuration() {
    if [[ "$SEARCH_SERVICE_NAME" == "CHANGE_ME" || -z "$SEARCH_SERVICE_NAME" ]]; then
        echo "ERROR: Set SEARCH_SERVICE_NAME before creating the search connection." >&2
        return 1
    fi
}

# Lists capability hosts configured for the Microsoft Foundry project.
list_capability_hosts() {
    az rest \
        --method get \
        --url "${MANAGEMENT_ENDPOINT}${PROJECT_RESOURCE_PATH}/capabilityHosts?api-version=${CAPABILITY_HOSTS_API_VERSION}" \
        --output json
}

# Deletes the current capability host before changing its dependent connections.
delete_capability_host() {
    az rest \
        --method delete \
        --url "${MANAGEMENT_ENDPOINT}${PROJECT_RESOURCE_PATH}/capabilityHosts/${CAPABILITY_HOST_NAME}?api-version=${CAPABILITY_HOSTS_API_VERSION}" \
        --output json
}

# Deletes the old Azure AI Search connection from the Microsoft Foundry project.
delete_old_search_connection() {
    az rest \
        --method delete \
        --url "${MANAGEMENT_ENDPOINT}${PROJECT_RESOURCE_PATH}/connections/${OLD_SEARCH_CONNECTION_NAME}?api-version=${CONNECTIONS_API_VERSION}" \
        --output json
}

# Creates or replaces the new Azure AI Search connection using system-assigned identity.
create_new_search_connection() {
    local body
    body=$(cat <<JSON
{
  "properties": {
    "connectionType": "AzureAISearch",
    "resourceId": "${SEARCH_RESOURCE_ID}",
    "credentials": {
      "identity": {
        "type": "SystemAssigned"
      }
    }
  }
}
JSON
)

    az rest \
        --method put \
        --url "${MANAGEMENT_ENDPOINT}${PROJECT_RESOURCE_PATH}/connections/${NEW_SEARCH_CONNECTION_NAME}?api-version=${CONNECTIONS_API_VERSION}" \
        --headers "Content-Type=application/json" \
        --body "$body" \
        --output json
}

# Creates or replaces the Agents capability host with vector, file, and thread storage connections.
create_capability_host() {
    local body
    body=$(cat <<JSON
{
  "properties": {
    "capabilityHostKind": "Agents",
    "vectorStoreConnections": [
      { "connectionName": "${NEW_SEARCH_CONNECTION_NAME}" }
    ],
    "storageConnections": [
      { "connectionName": "${STORAGE_CONNECTION_NAME}" }
    ],
    "threadStorageConnections": [
      { "connectionName": "${COSMOS_CONNECTION_NAME}" }
    ]
  }
}
JSON
)

    az rest \
        --method put \
        --url "${MANAGEMENT_ENDPOINT}${PROJECT_RESOURCE_PATH}/capabilityHosts/${CAPABILITY_HOST_NAME}?api-version=${CAPABILITY_HOSTS_API_VERSION}" \
        --headers "Content-Type=application/json" \
        --body "$body" \
        --output json
}

# Each function call is intentionally separate to support breakpoints and F10/F11 debugging.
main() {
    initialize_azure_context
    validate_configuration

    list_capability_hosts
    delete_capability_host
    delete_old_search_connection
    create_new_search_connection
    create_capability_host

    list_capability_hosts
}

main "$@"
