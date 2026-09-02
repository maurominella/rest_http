#!/usr/bin/env bash

# Contains Azure CLI operations intended to be run one selection at a time.
# Do not press F5 unless you want to execute the entire file.
# In VS Code, use "Terminal: Run Selected Text in Active Terminal".
# Authenticate first with: az login --use-device-code
# When multiple subscriptions are available, this script selects SUBID explicitly.

### Azure resource configuration. These values are not secrets.

ID="aif02"

SUBID="eca2eddb-0f0c-4351-a634-52751499eeea"
LOCATION="swedencentral"

# Resource Groups
NETWORKING_RG="${ID}_networking_rg"
FOUNDRY_RG="${ID}_foundry_rg"
RESOURCES_RG="${ID}_resources_rg"
JUMPVM_RG="${ID}_jumpvm_rg"
DNS_RG="dns-private-rg"

### Virtual Network Configuration
VNET_NAME="${ID}_vnet"
VNET_ADDRESS_PREFIX="192.168.0.0/16"
VNET_RESOURCE_ID="/subscriptions/${SUBID}/resourceGroups/${NETWORKING_RG}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}"
FOUNDRY_SUBNET_NAME="foundry_subnet"
FOUNDRY_SUBNET_PREFIX="192.168.1.0/24"
COGNITIVE_SERVICES_SERVICE_ENDPOINT="Microsoft.CognitiveServices"
RESOURCES_SUBNET_NAME="resources_subnet"
RESOURCES_SUBNET_PREFIX="192.168.2.0/24"
AGENTS_DELEGATED_SUBNET_NAME="agentsdelegated_subnet"
AGENTS_DELEGATED_SUBNET_PREFIX="192.168.3.0/24"
AGENTS_DELEGATED_SUBNET_RESOURCE_ID="${VNET_RESOURCE_ID}/subnets/${AGENTS_DELEGATED_SUBNET_NAME}"
CONTAINER_APPS_SUBNET_DELEGATION="Microsoft.App/environments"
PE_SUBNET_NAME="pe_subnet"
PE_SUBNET_PREFIX="192.168.4.0/24"
JUMP_SUBNET_NAME="jump_subnet"
JUMP_SUBNET_PREFIX="192.168.5.0/24"
JUMP_VM_SIZE="Standard_DS1_v2"
JUMP_VM_IMAGE="MicrosoftWindowsDesktop:windows-11:win11-24h2-pro:latest"
PRIVATE_ENDPOINT_API_VERSION="2025-07-01"
PRIVATE_ENDPOINT_POLL_INTERVAL_SECONDS=10
PRIVATE_ENDPOINT_POLL_TIMEOUT_SECONDS=1800
MANAGEMENT_ENDPOINT="https://management.azure.com"

### Storage Account Configuration
STORAGE_ACCOUNT_NAME="${ID}storage"
STORAGE_ACCOUNT_SKU="Standard_LRS"
STORAGE_PRIVATE_ENDPOINT_NAME="${STORAGE_ACCOUNT_NAME}-pe"
STORAGE_PRIVATE_DNS_SUB_TARGET="blob"
STORAGE_PRIVATE_DNS_ZONE="privatelink.blob.core.windows.net"
STORAGE_PRIVATE_DNS_VNET_LINK_NAME="dns-${STORAGE_ACCOUNT_NAME}-vnetlink"

### Azure Cognitive Search Configuration
SEARCH_SERVICE_NAME="${ID}-aisearch"
SEARCH_SERVICE_SKU="basic"
SEARCH_PRIVATE_ENDPOINT_NAME="${SEARCH_SERVICE_NAME}-pe"
SEARCH_PRIVATE_DNS_SUB_TARGET="searchService"
SEARCH_PRIVATE_DNS_ZONE="privatelink.search.windows.net"
SEARCH_PRIVATE_DNS_VNET_LINK_NAME="dns-${SEARCH_SERVICE_NAME}-vnetlink"
SEARCH_RESOURCE_ID="/subscriptions/${SUBID}/resourceGroups/${RESOURCES_RG}/providers/Microsoft.Search/searchServices/${SEARCH_SERVICE_NAME}"

### Cosmos DB Configuration
COSMOSDB_SERVICE_NAME="${ID}-cosmosdb"
COSMOSDB_PRIVATE_ENDPOINT_NAME="${COSMOSDB_SERVICE_NAME}-pe"
COSMOSDB_PRIVATE_DNS_SUB_TARGET="sql"
COSMOSDB_PRIVATE_DNS_ZONE="privatelink.documents.azure.com"
COSMOSDB_PRIVATE_DNS_VNET_LINK_NAME="dns-${COSMOSDB_SERVICE_NAME}-vnetlink"
COSMOSDB_RESOURCE_ID="/subscriptions/${SUBID}/resourceGroups/${RESOURCES_RG}/providers/Microsoft.DocumentDB/databaseAccounts/${COSMOSDB_SERVICE_NAME}"

### Foundry Service Configuration
FOUNDRY_SERVICE_NAME="${ID}-foundry"
FOUNDRY_RESOURCE_ID="/subscriptions/${SUBID}/resourceGroups/${FOUNDRY_RG}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_SERVICE_NAME}"
FOUNDRY_PRIVATE_ENDPOINT_NAME="${FOUNDRY_SERVICE_NAME}-pe"
FOUNDRY_PRIVATE_DNS_SUB_TARGET="account"
FOUNDRY_COGNITIVE_PRIVATE_DNS_ZONE="privatelink.cognitiveservices.azure.com"
FOUNDRY_OPENAI_PRIVATE_DNS_ZONE="privatelink.openai.azure.com"
FOUNDRY_SERVICES_PRIVATE_DNS_ZONE="privatelink.services.ai.azure.com"
FOUNDRY_COGNITIVE_DNS_VNET_LINK_NAME="dns-${FOUNDRY_SERVICE_NAME}-cognitive-vnetlink"
FOUNDRY_OPENAI_DNS_VNET_LINK_NAME="dns-${FOUNDRY_SERVICE_NAME}-openai-vnetlink"
FOUNDRY_SERVICES_DNS_VNET_LINK_NAME="dns-${FOUNDRY_SERVICE_NAME}-services-vnetlink"
FOUNDRY_PROJECT_NAME="${ID}-project01"
FOUNDRY_CAPABILITY_HOST_NAME="agentscaphost"
FOUNDRY_API_VERSION="2025-04-01-preview"
FOUNDRY_CAPABILITY_HOST_API_VERSION="2025-06-01"
FOUNDRY_POLL_INTERVAL_SECONDS=10
FOUNDRY_POLL_TIMEOUT_SECONDS=1800

### Jump VM Configuration
JUMPVM_NAME="${ID}-jumpvm"
JUMPVM_USERNAME="mauromi"



###

create_resource_group_if_missing() {
	local resource_group_name="$1"

	echo "Checking whether resource group '${resource_group_name}' exists in subscription '${SUBID}'..."
	if az group show \
		--name "${resource_group_name}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none 2>/dev/null; then
		echo "Resource group '${resource_group_name}' already exists; creation skipped."
		return
	fi

	echo "Creating resource group '${resource_group_name}' in '${LOCATION}'..."
	if az group create \
		--name "${resource_group_name}" \
		--location "${LOCATION}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none; then
		echo "Resource group '${resource_group_name}' created successfully."
		return
	fi

	echo "Failed to create resource group '${resource_group_name}'." >&2
	return 1
}

create_vnet_if_missing() {
	local vnet_name="$1"
	local resource_group_name="$2"
	local address_prefix="$3"

	echo "Checking whether virtual network '${vnet_name}' exists in resource group '${resource_group_name}'..."
	if az network vnet show \
		--name "${vnet_name}" \
		--resource-group "${resource_group_name}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none 2>/dev/null; then
		echo "Virtual network '${vnet_name}' already exists in resource group '${resource_group_name}'; creation skipped."
		return
	fi

	echo "Creating virtual network '${vnet_name}' with address space '${address_prefix}' in resource group '${resource_group_name}'..."
	if az network vnet create \
		--name "${vnet_name}" \
		--resource-group "${resource_group_name}" \
		--location "${LOCATION}" \
		--address-prefixes "${address_prefix}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none; then
		echo "Virtual network '${vnet_name}' created successfully."
		return
	fi

	echo "Failed to create virtual network '${vnet_name}'. Review the Azure CLI error above." >&2
	return 1
}

create_subnet_if_missing() {
	local vnet_name="$1"
	local subnet_name="$2"
	local address_prefix="$3"
	local resource_group_name="$4"
	local service_endpoint="$5"
	local delegation="$6"
	local default_outbound_access="${7:-false}"

	echo "Checking whether subnet '${subnet_name}' exists in virtual network '${vnet_name}'..."
	if az network vnet subnet show \
		--name "${subnet_name}" \
		--vnet-name "${vnet_name}" \
		--resource-group "${resource_group_name}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none 2>/dev/null; then
		echo "Subnet '${subnet_name}' already exists in virtual network '${vnet_name}'; creation skipped."
		return
	fi

	echo "Creating private subnet '${subnet_name}' with address prefix '${address_prefix}' in virtual network '${vnet_name}'..."
	if ! az network vnet subnet create \
		--name "${subnet_name}" \
		--vnet-name "${vnet_name}" \
		--resource-group "${resource_group_name}" \
		--address-prefixes "${address_prefix}" \
		--default-outbound "${default_outbound_access}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none; then
		echo "Failed to create subnet '${subnet_name}'. Review the Azure CLI error above." >&2
		return 1
	fi

	if [[ -n "${service_endpoint}" ]]; then
		echo "Adding service endpoint '${service_endpoint}' to subnet '${subnet_name}'..."
		if ! az network vnet subnet update \
			--name "${subnet_name}" \
			--vnet-name "${vnet_name}" \
			--resource-group "${resource_group_name}" \
			--service-endpoints "${service_endpoint}" \
			--subscription "${SUBID}" \
			--only-show-errors \
			--output none; then
			echo "Failed to add service endpoint '${service_endpoint}' to subnet '${subnet_name}'." >&2
			return 1
		fi
	fi

	if [[ -n "${delegation}" ]]; then
		echo "Adding delegation '${delegation}' to subnet '${subnet_name}'..."
		if ! az network vnet subnet update \
			--name "${subnet_name}" \
			--vnet-name "${vnet_name}" \
			--resource-group "${resource_group_name}" \
			--delegations "${delegation}" \
			--subscription "${SUBID}" \
			--only-show-errors \
			--output none; then
			echo "Failed to add delegation '${delegation}' to subnet '${subnet_name}'." >&2
			return 1
		fi
	fi

	echo "Subnet '${subnet_name}' created and configured successfully."
}

create_jumpvm() {
	local jumpvm_name="$1"
	local resource_group="$2"
	local vnet_name="$3"
	local subnet_name="$4"
	local location="$5"
	local username="$6"
	local pwd="$7"
	local computer_name="${jumpvm_name//[^[:alnum:]-]/-}"
	local public_ip_name="${jumpvm_name}-pip"
	local nsg_name="${jumpvm_name}-nsg"
	local subnet_resource_id=""

	if [[ -z "${jumpvm_name}" || -z "${resource_group}" || -z "${vnet_name}" || -z "${subnet_name}" || -z "${location}" || -z "${username}" || -z "${pwd}" ]]; then
		echo "VM name, resource group, VNet name, subnet name, location, username, and password are required." >&2
		return 1
	fi

	if ! IFS= read -r subnet_resource_id < <(
		az network vnet subnet show \
			--name "${subnet_name}" \
			--vnet-name "${vnet_name}" \
			--resource-group "${NETWORKING_RG}" \
			--subscription "${SUBID}" \
			--query id \
			--output tsv \
			--only-show-errors
	); then
		echo "Unable to find subnet '${subnet_name}' in VNet '${vnet_name}' and resource group '${NETWORKING_RG}'." >&2
		return 1
	fi

	if az vm show \
		--name "${jumpvm_name}" \
		--resource-group "${resource_group}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none 2>/dev/null; then
		echo "Jump VM '${jumpvm_name}' already exists in resource group '${resource_group}'; creation skipped."
		return
	fi

	# No --zone or --availability-set is supplied: no infrastructure redundancy is requested.
	# Standard_LRS minimizes disk cost; --nsg-rule RDP permits inbound TCP/3389.
	echo "Creating Windows 11 jump VM '${jumpvm_name}' in subnet '${subnet_name}'..."
	if az vm create \
		--name "${jumpvm_name}" \
		--computer-name "${computer_name:0:15}" \
		--resource-group "${resource_group}" \
		--location "${location}" \
		--subnet "${subnet_resource_id}" \
		--size "${JUMP_VM_SIZE}" \
		--image "${JUMP_VM_IMAGE}" \
		--admin-username "${username}" \
		--admin-password "${pwd}" \
		--license-type Windows_Client \
		--storage-sku Standard_LRS \
		--public-ip-address "${public_ip_name}" \
		--public-ip-sku Standard \
		--nsg "${nsg_name}" \
		--nsg-rule RDP \
		--nic-delete-option Delete \
		--os-disk-delete-option Delete \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none; then
		pwd=""
		echo "Jump VM '${jumpvm_name}' created successfully with Azure Hybrid Benefit and RDP enabled."
		return
	fi

	echo "Failed to create jump VM '${jumpvm_name}'. Review the Azure CLI error above." >&2
	return 1
}

create_private_endpoint_if_missing() {
	local private_endpoint_resource_group="$1"
	local target_resource_id="$2"
	local target_subresource="$3"
	local private_ip_configuration="${4:-dynamic}"
	local private_endpoint_name="$5"
	local vnet_name="${6:-${VNET_NAME}}"
	local subnet_name="${7:-${PE_SUBNET_NAME}}"
	local vnet_resource_group="${8:-${NETWORKING_RG}}"
	local network_interface_name="${private_endpoint_name}-nic"
	local connection_name="${private_endpoint_name}-connection"
	local ip_configuration_name="${private_endpoint_name}-ipconfig"
	local subnet_resource_id="/subscriptions/${SUBID}/resourceGroups/${vnet_resource_group}/providers/Microsoft.Network/virtualNetworks/${vnet_name}/subnets/${subnet_name}"
	local private_endpoint_url="${MANAGEMENT_ENDPOINT}/subscriptions/${SUBID}/resourceGroups/${private_endpoint_resource_group}/providers/Microsoft.Network/privateEndpoints/${private_endpoint_name}?api-version=${PRIVATE_ENDPOINT_API_VERSION}"

	echo "Checking whether private endpoint '${private_endpoint_name}' exists in resource group '${private_endpoint_resource_group}'..."
	if az network private-endpoint show \
		--name "${private_endpoint_name}" \
		--resource-group "${private_endpoint_resource_group}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none 2>/dev/null; then
		echo "Private endpoint '${private_endpoint_name}' already exists in resource group '${private_endpoint_resource_group}'; creation skipped."
		return
	fi

	if [[ -z "${target_resource_id}" || -z "${target_subresource}" || -z "${private_endpoint_name}" ]]; then
		echo "Target resource ID, target subresource, and private endpoint name are required." >&2
		return 1
	fi

	echo "Creating private endpoint '${private_endpoint_name}' for subresource '${target_subresource}' with network interface '${network_interface_name}' and private link service connection '${connection_name}'..."
	if [[ "${private_ip_configuration}" == "dynamic" || "${private_ip_configuration}" == "Dynamic" ]]; then
		if az rest \
			--method put \
			--url "${private_endpoint_url}" \
			--body "{\"location\":\"${LOCATION}\",\"properties\":{\"customNetworkInterfaceName\":\"${network_interface_name}\",\"ipVersionType\":\"IPv4\",\"privateLinkServiceConnections\":[{\"name\":\"${connection_name}\",\"properties\":{\"groupIds\":[\"${target_subresource}\"],\"privateLinkServiceId\":\"${target_resource_id}\"}}],\"subnet\":{\"id\":\"${subnet_resource_id}\"}}}" \
			--only-show-errors \
			--output none; then
			echo "Private endpoint '${private_endpoint_name}' created successfully with dynamic private IP allocation."
			return
		fi
	else
		if az rest \
			--method put \
			--url "${private_endpoint_url}" \
			--body "{\"location\":\"${LOCATION}\",\"properties\":{\"customNetworkInterfaceName\":\"${network_interface_name}\",\"ipConfigurations\":[{\"name\":\"${ip_configuration_name}\",\"properties\":{\"groupId\":\"${target_subresource}\",\"memberName\":\"${target_subresource}\",\"privateIPAddress\":\"${private_ip_configuration}\"}}],\"ipVersionType\":\"IPv4\",\"privateLinkServiceConnections\":[{\"name\":\"${connection_name}\",\"properties\":{\"groupIds\":[\"${target_subresource}\"],\"privateLinkServiceId\":\"${target_resource_id}\"}}],\"subnet\":{\"id\":\"${subnet_resource_id}\"}}}" \
			--only-show-errors \
			--output none; then
			echo "Private endpoint '${private_endpoint_name}' created successfully with static private IP '${private_ip_configuration}'."
			return
		fi
	fi

	echo "Failed to create private endpoint '${private_endpoint_name}'. Review the Azure CLI error above." >&2
	return 1
}

wait_for_private_endpoint_succeeded() {
	local subscription_id="$1"
	local resource_group_name="$2"
	local private_endpoint_name="$3"
	local poll_interval_seconds="${4:-${PRIVATE_ENDPOINT_POLL_INTERVAL_SECONDS}}"
	local timeout_seconds="${5:-${PRIVATE_ENDPOINT_POLL_TIMEOUT_SECONDS}}"
	local elapsed_seconds=0
	local provisioning_state=""

	echo "Waiting for private endpoint '${private_endpoint_name}' to reach provisioning state 'Succeeded'..."
	while (( elapsed_seconds <= timeout_seconds )); do
		if ! IFS= read -r provisioning_state < <(
			az network private-endpoint show \
				--name "${private_endpoint_name}" \
				--resource-group "${resource_group_name}" \
				--subscription "${subscription_id}" \
				--query provisioningState \
				--output tsv \
				--only-show-errors
		); then
			echo "Unable to read the provisioning state of private endpoint '${private_endpoint_name}'." >&2
			return 1
		fi

		case "${provisioning_state}" in
			Succeeded)
				echo "Private endpoint '${private_endpoint_name}' provisioning completed successfully."
				return
				;;
			Failed | Canceled | Deleted)
				echo "Private endpoint '${private_endpoint_name}' reached terminal provisioning state '${provisioning_state}'." >&2
				return 1
				;;
		esac

		if (( elapsed_seconds == timeout_seconds )); then
			break
		fi

		echo "Private endpoint '${private_endpoint_name}' is '${provisioning_state:-Unknown}'. Checking again in ${poll_interval_seconds} seconds..."
		sleep "${poll_interval_seconds}"
		(( elapsed_seconds += poll_interval_seconds ))
	done

	echo "Timed out after ${timeout_seconds} seconds waiting for private endpoint '${private_endpoint_name}' to reach provisioning state 'Succeeded'." >&2
	return 1
}

AddDnsZoneConfiguration() {
	local subscription_id="$1"
	local dns_resource_group="$2"
	local sub_target="$3"
	local private_dns_zone="$4"
	local private_endpoint_resource_group="$5"
	local private_endpoint_name="$6"
	local dns_zone_group_name="${7:-default}"
	local configuration_name="${8:-privatelink_${sub_target//./_}_windows_net}"
	local private_dns_zone_id="/subscriptions/${subscription_id}/resourceGroups/${dns_resource_group}/providers/Microsoft.Network/privateDnsZones/${private_dns_zone}"

	echo "Checking whether Private DNS zone '${private_dns_zone}' exists in resource group '${dns_resource_group}'..."
	if ! az network private-dns zone show \
		--name "${private_dns_zone}" \
		--resource-group "${dns_resource_group}" \
		--subscription "${subscription_id}" \
		--only-show-errors \
		--output none 2>/dev/null; then
		echo "Creating Private DNS zone '${private_dns_zone}' in resource group '${dns_resource_group}'..."
		if ! az network private-dns zone create \
			--name "${private_dns_zone}" \
			--resource-group "${dns_resource_group}" \
			--subscription "${subscription_id}" \
			--only-show-errors \
			--output none; then
			echo "Failed to create Private DNS zone '${private_dns_zone}'. Review the Azure CLI error above." >&2
			return 1
		fi
		echo "Private DNS zone '${private_dns_zone}' created successfully."
	else
		echo "Private DNS zone '${private_dns_zone}' already exists; creation skipped."
	fi

	if ! wait_for_private_endpoint_succeeded \
		"${subscription_id}" \
		"${private_endpoint_resource_group}" \
		"${private_endpoint_name}"; then
		echo "DNS zone group configuration cannot continue until private endpoint '${private_endpoint_name}' is provisioned successfully." >&2
		return 1
	fi

	echo "Checking whether DNS zone group '${dns_zone_group_name}' exists on private endpoint '${private_endpoint_name}'..."
	if az network private-endpoint dns-zone-group show \
		--endpoint-name "${private_endpoint_name}" \
		--name "${dns_zone_group_name}" \
		--resource-group "${private_endpoint_resource_group}" \
		--subscription "${subscription_id}" \
		--only-show-errors \
		--output none 2>/dev/null; then
		echo "DNS zone group '${dns_zone_group_name}' already exists; adding or updating configuration '${configuration_name}'..."
		if az network private-endpoint dns-zone-group add \
			--endpoint-name "${private_endpoint_name}" \
			--name "${dns_zone_group_name}" \
			--private-dns-zone "${private_dns_zone_id}" \
			--zone-name "${configuration_name}" \
			--resource-group "${private_endpoint_resource_group}" \
			--subscription "${subscription_id}" \
			--only-show-errors \
			--output none; then
			echo "DNS configuration '${configuration_name}' added or updated successfully."
			return
		fi

		echo "Failed to add or update DNS configuration '${configuration_name}'. Review the Azure CLI error above." >&2
		return 1
	fi

	echo "Creating DNS zone group '${dns_zone_group_name}' with configuration '${configuration_name}' on private endpoint '${private_endpoint_name}'..."
	if az network private-endpoint dns-zone-group create \
		--endpoint-name "${private_endpoint_name}" \
		--name "${dns_zone_group_name}" \
		--private-dns-zone "${private_dns_zone_id}" \
		--zone-name "${configuration_name}" \
		--resource-group "${private_endpoint_resource_group}" \
		--subscription "${subscription_id}" \
		--only-show-errors \
		--output none; then
		echo "DNS zone group '${dns_zone_group_name}' and configuration '${configuration_name}' created successfully."
		return
	fi

	echo "Failed to add DNS configuration '${configuration_name}'. Review the Azure CLI error above." >&2
	return 1
}

create_private_dns_vnet_link_if_missing() {
	local subscription_id="$1"
	local dns_resource_group="$2"
	local private_dns_zone="$3"
	local virtual_network="$4"
	local link_name="$5"

	echo "Checking whether virtual network link '${link_name}' exists in Private DNS zone '${private_dns_zone}'..."
	if az network private-dns link vnet show \
		--name "${link_name}" \
		--zone-name "${private_dns_zone}" \
		--resource-group "${dns_resource_group}" \
		--subscription "${subscription_id}" \
		--only-show-errors \
		--output none 2>/dev/null; then
		echo "Virtual network link '${link_name}' already exists in Private DNS zone '${private_dns_zone}'; creation skipped."
		return
	fi

	echo "Creating virtual network link '${link_name}' between Private DNS zone '${private_dns_zone}' and virtual network '${virtual_network}'..."
	if az network private-dns link vnet create \
		--name "${link_name}" \
		--zone-name "${private_dns_zone}" \
		--resource-group "${dns_resource_group}" \
		--virtual-network "${virtual_network}" \
		--registration-enabled false \
		--resolution-policy Default \
		--subscription "${subscription_id}" \
		--only-show-errors \
		--output none; then
		echo "Virtual network link '${link_name}' created successfully with auto-registration and internet fallback disabled."
		return
	fi

	echo "Failed to create virtual network link '${link_name}'. Review the Azure CLI error above." >&2
	return 1
}

create_storage_account_if_missing() {
	local storage_account_name="$1"
	local resource_group_name="$2"

	if az storage account show \
		--name "${storage_account_name}" \
		--resource-group "${resource_group_name}" \
		--subscription "${SUBID}" \
		--output none 2>/dev/null; then
		echo "Storage account '${storage_account_name}' already exists in resource group '${resource_group_name}'; creation skipped."
		return
	fi

	echo "Creating storage account '${storage_account_name}' in resource group '${resource_group_name}' and location '${LOCATION}'..."
	if az storage account create \
		--name "${storage_account_name}" \
		--resource-group "${resource_group_name}" \
		--location "${LOCATION}" \
		--sku "${STORAGE_ACCOUNT_SKU}" \
		--kind StorageV2 \
		--access-tier Hot \
		--enable-hierarchical-namespace false \
		--https-only true \
		--min-tls-version TLS1_2 \
		--allow-blob-public-access false \
		--public-network-access Enabled \
		--default-action Allow \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none; then
		echo "Storage account '${storage_account_name}' created successfully in resource group '${resource_group_name}'."
		return
	fi

	echo "Failed to create storage account '${storage_account_name}'. Review the Azure CLI error above." >&2
	return 1
}

create_aisearch_if_missing() {
	local search_service_name="$1"
	local resource_group_name="$2"

	echo "Checking whether Azure AI Search service '${search_service_name}' exists in resource group '${resource_group_name}'..."
	if az search service show \
		--name "${search_service_name}" \
		--resource-group "${resource_group_name}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none 2>/dev/null; then
		echo "Azure AI Search service '${search_service_name}' already exists in resource group '${resource_group_name}'; creation skipped."
		return
	fi

	echo "Creating Azure AI Search service '${search_service_name}' in resource group '${resource_group_name}' and location '${LOCATION}'..."
	if az search service create \
		--name "${search_service_name}" \
		--resource-group "${resource_group_name}" \
		--location "${LOCATION}" \
		--sku "${SEARCH_SERVICE_SKU}" \
		--replica-count 1 \
		--partition-count 1 \
		--semantic-search free \
		--auth-options aadOrApiKey \
		--aad-auth-failure-mode http401WithBearerChallenge \
		--public-network-access enabled \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none; then
		echo "Azure AI Search service '${search_service_name}' created successfully."
		return
	fi

	echo "Failed to create Azure AI Search service '${search_service_name}'. Review the Azure CLI error above." >&2
	return 1
}

create_cosmosdb_if_missing() {
	local service_name="$1"
	local resource_group_name="$2"
	local location="${3:-${LOCATION}}"

	echo "Checking whether Azure Cosmos DB account '${service_name}' exists in resource group '${resource_group_name}'..."
	if az cosmosdb show \
		--name "${service_name}" \
		--resource-group "${resource_group_name}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none 2>/dev/null; then
		echo "Azure Cosmos DB account '${service_name}' already exists in resource group '${resource_group_name}'; creation skipped."
		return
	fi

	echo "Creating single-region serverless Azure Cosmos DB for NoSQL account '${service_name}' in '${location}'..."
	if az cosmosdb create \
		--name "${service_name}" \
		--resource-group "${resource_group_name}" \
		--kind GlobalDocumentDB \
		--locations regionName="${location}" failoverPriority=0 isZoneRedundant=False \
		--capabilities EnableServerless \
		--public-network-access Enabled \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none; then
		echo "Azure Cosmos DB for NoSQL account '${service_name}' created successfully with serverless capacity, one region, and public network access."
		return
	fi

	echo "Failed to create Azure Cosmos DB account '${service_name}'. Review the Azure CLI error above." >&2
	return 1
}

assign_role_if_missing() {
	local principal_id="$1"
	local role_definition_id="$2"
	local scope="$3"
	local role_name="$4"
	local existing_assignment_id=""

	if ! IFS= read -r existing_assignment_id < <(
		az role assignment list \
			--assignee-object-id "${principal_id}" \
			--role "${role_definition_id}" \
			--scope "${scope}" \
			--subscription "${SUBID}" \
			--query '[0].id' \
			--output tsv \
			--only-show-errors
	); then
		echo "Failed to check role '${role_name}' for principal '${principal_id}'." >&2
		return 1
	fi

	if [[ -n "${existing_assignment_id}" ]]; then
		echo "Role '${role_name}' is already assigned on '${scope}'; assignment skipped."
		return
	fi

	echo "Assigning role '${role_name}' on '${scope}'..."
	if az role assignment create \
		--assignee-object-id "${principal_id}" \
		--assignee-principal-type ServicePrincipal \
		--role "${role_definition_id}" \
		--scope "${scope}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none; then
		echo "Role '${role_name}' assigned successfully."
		return
	fi

	echo "Failed to assign role '${role_name}' on '${scope}'." >&2
	return 1
}

wait_for_foundry_resource_succeeded() {
	local resource_url="$1"
	local resource_label="$2"
	local elapsed_seconds=0
	local provisioning_state=""

	echo "Waiting for ${resource_label} to reach provisioning state 'Succeeded'..."
	while (( elapsed_seconds <= FOUNDRY_POLL_TIMEOUT_SECONDS )); do
		if ! IFS= read -r provisioning_state < <(
			az rest \
				--method get \
				--url "${resource_url}" \
				--query properties.provisioningState \
				--output tsv \
				--only-show-errors
		); then
			echo "Unable to read the provisioning state of ${resource_label}." >&2
			return 1
		fi

		case "${provisioning_state}" in
			Succeeded)
				echo "${resource_label} provisioning completed successfully."
				return
				;;
			Failed | Canceled | Deleted)
				echo "${resource_label} reached terminal provisioning state '${provisioning_state}'." >&2
				return 1
				;;
		esac

		if (( elapsed_seconds == FOUNDRY_POLL_TIMEOUT_SECONDS )); then
			break
		fi

		echo "${resource_label} is '${provisioning_state:-Unknown}'. Checking again in ${FOUNDRY_POLL_INTERVAL_SECONDS} seconds..."
		sleep "${FOUNDRY_POLL_INTERVAL_SECONDS}"
		(( elapsed_seconds += FOUNDRY_POLL_INTERVAL_SECONDS ))
	done

	echo "Timed out after ${FOUNDRY_POLL_TIMEOUT_SECONDS} seconds waiting for ${resource_label}." >&2
	return 1
}

disable_public_network_access_if_private_ready() {
	local network_injection_subnet_id=""
	local private_endpoint_name=""
	local private_endpoint_status=""
	local private_endpoint_names=(
		"${STORAGE_PRIVATE_ENDPOINT_NAME}"
		"${SEARCH_PRIVATE_ENDPOINT_NAME}"
		"${COSMOSDB_PRIVATE_ENDPOINT_NAME}"
		"${FOUNDRY_PRIVATE_ENDPOINT_NAME}"
	)

	if ! network_injection_subnet_id="$(
		az cognitiveservices account show \
			--name "${FOUNDRY_SERVICE_NAME}" \
			--resource-group "${FOUNDRY_RG}" \
			--subscription "${SUBID}" \
			--query "properties.networkInjections[?scenario=='agent'].subnetArmId | [0]" \
			--output tsv \
			--only-show-errors
	)"; then
		echo "Unable to inspect Foundry network injection." >&2
		return 1
	fi

	if [[ "${network_injection_subnet_id,,}" != "${AGENTS_DELEGATED_SUBNET_RESOURCE_ID,,}" ]]; then
		echo "Public access was not changed: the Foundry account is not injected into '${AGENTS_DELEGATED_SUBNET_RESOURCE_ID}'." >&2
		echo "Redeploy the Foundry account with networkInjections.scenario='agent' before making its capability-host dependencies private." >&2
		return 1
	fi

	for private_endpoint_name in "${private_endpoint_names[@]}"; do
		if ! IFS= read -r private_endpoint_status < <(
			az network private-endpoint show \
				--name "${private_endpoint_name}" \
				--resource-group "${NETWORKING_RG}" \
				--subscription "${SUBID}" \
				--query "join('/', [provisioningState, privateLinkServiceConnections[0].privateLinkServiceConnectionState.status])" \
				--output tsv \
				--only-show-errors
		); then
			echo "Public access was not changed: private endpoint '${private_endpoint_name}' could not be inspected." >&2
			return 1
		fi

		if [[ "${private_endpoint_status}" != "Succeeded/Approved" ]]; then
			echo "Public access was not changed: private endpoint '${private_endpoint_name}' is '${private_endpoint_status}', not 'Succeeded/Approved'." >&2
			return 1
		fi
	done

	echo "Disabling public network access on Foundry and its capability-host dependencies..."
	az resource update --ids "${FOUNDRY_RESOURCE_ID}" --set properties.publicNetworkAccess=Disabled properties.networkAcls.defaultAction=Deny properties.networkAcls.bypass=AzureServices --subscription "${SUBID}" --only-show-errors --output none || return 1
	az storage account update --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCES_RG}" --public-network-access Disabled --default-action Deny --bypass AzureServices --subscription "${SUBID}" --only-show-errors --output none || return 1
	az search service update --name "${SEARCH_SERVICE_NAME}" --resource-group "${RESOURCES_RG}" --public-network-access disabled --subscription "${SUBID}" --only-show-errors --output none || return 1
	az cosmosdb update --name "${COSMOSDB_SERVICE_NAME}" --resource-group "${RESOURCES_RG}" --public-network-access Disabled --subscription "${SUBID}" --only-show-errors --output none || return 1
	echo "Public network access disabled on Foundry, Storage, Azure AI Search, and Cosmos DB."
}

create_foundry_if_missing() {
	local service_name="$1"
	local resource_group_name="$2"
	local location="${3:-${LOCATION}}"
	local project_name="${4:-${FOUNDRY_PROJECT_NAME}}"
	local account_resource_path="/subscriptions/${SUBID}/resourceGroups/${resource_group_name}/providers/Microsoft.CognitiveServices/accounts/${service_name}"
	local project_resource_path="${account_resource_path}/projects/${project_name}"
	local storage_resource_id="/subscriptions/${SUBID}/resourceGroups/${RESOURCES_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}"
	local search_resource_id="/subscriptions/${SUBID}/resourceGroups/${RESOURCES_RG}/providers/Microsoft.Search/searchServices/${SEARCH_SERVICE_NAME}"
	local cosmosdb_resource_id="/subscriptions/${SUBID}/resourceGroups/${RESOURCES_RG}/providers/Microsoft.DocumentDB/databaseAccounts/${COSMOSDB_SERVICE_NAME}"
	local storage_connection_url="${MANAGEMENT_ENDPOINT}${project_resource_path}/connections/${STORAGE_ACCOUNT_NAME}?api-version=${FOUNDRY_API_VERSION}"
	local search_connection_url="${MANAGEMENT_ENDPOINT}${project_resource_path}/connections/${SEARCH_SERVICE_NAME}?api-version=${FOUNDRY_API_VERSION}"
	local cosmosdb_connection_url="${MANAGEMENT_ENDPOINT}${project_resource_path}/connections/${COSMOSDB_SERVICE_NAME}?api-version=${FOUNDRY_API_VERSION}"
	local project_capability_host_url="${MANAGEMENT_ENDPOINT}${project_resource_path}/capabilityHosts/${FOUNDRY_CAPABILITY_HOST_NAME}?api-version=${FOUNDRY_CAPABILITY_HOST_API_VERSION}"
	local project_principal_id=""

	echo "Checking whether Microsoft Foundry account '${service_name}' exists in resource group '${resource_group_name}'..."
	if ! az cognitiveservices account show \
		--name "${service_name}" \
		--resource-group "${resource_group_name}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none 2>/dev/null; then
		echo "Creating network-injected Microsoft Foundry account '${service_name}' in '${location}'..."
		if ! az rest \
			--method put \
			--url "${MANAGEMENT_ENDPOINT}${account_resource_path}?api-version=${FOUNDRY_API_VERSION}" \
			--body "{\"location\":\"${location}\",\"kind\":\"AIServices\",\"sku\":{\"name\":\"S0\"},\"identity\":{\"type\":\"SystemAssigned\"},\"properties\":{\"allowProjectManagement\":true,\"customSubDomainName\":\"${service_name}\",\"publicNetworkAccess\":\"Disabled\",\"networkAcls\":{\"defaultAction\":\"Deny\",\"virtualNetworkRules\":[],\"ipRules\":[],\"bypass\":\"AzureServices\"},\"networkInjections\":[{\"scenario\":\"agent\",\"subnetArmId\":\"${AGENTS_DELEGATED_SUBNET_RESOURCE_ID}\",\"useMicrosoftManagedNetwork\":false}]}}" \
			--only-show-errors \
			--output none; then
			echo "Failed to create Microsoft Foundry account '${service_name}'." >&2
			return 1
		fi
		echo "Microsoft Foundry account '${service_name}' created with VNet injection and public network access disabled."
		wait_for_foundry_resource_succeeded "${MANAGEMENT_ENDPOINT}${account_resource_path}?api-version=${FOUNDRY_API_VERSION}" "Microsoft Foundry account '${service_name}'" || return 1
	else
		echo "Microsoft Foundry account '${service_name}' already exists; creation skipped."
	fi

	echo "Checking whether Foundry project '${project_name}' exists..."
	if ! az cognitiveservices account project show \
		--name "${service_name}" \
		--project-name "${project_name}" \
		--resource-group "${resource_group_name}" \
		--subscription "${SUBID}" \
		--only-show-errors \
		--output none 2>/dev/null; then
		echo "Creating Foundry project '${project_name}'..."
		if ! az cognitiveservices account project create \
			--name "${service_name}" \
			--project-name "${project_name}" \
			--resource-group "${resource_group_name}" \
			--location "${location}" \
			--display-name "${project_name}" \
			--description "Standard Agent Setup using customer-owned Storage, AI Search, and Cosmos DB" \
			--assign-identity \
			--subscription "${SUBID}" \
			--only-show-errors \
			--output none; then
			echo "Failed to create Foundry project '${project_name}'." >&2
			return 1
		fi
		echo "Foundry project '${project_name}' created successfully."
	else
		echo "Foundry project '${project_name}' already exists; creation skipped."
	fi

	if ! IFS= read -r project_principal_id < <(
		az cognitiveservices account project show \
			--name "${service_name}" \
			--project-name "${project_name}" \
			--resource-group "${resource_group_name}" \
			--subscription "${SUBID}" \
			--query identity.principalId \
			--output tsv \
			--only-show-errors
	); then
		echo "Failed to retrieve the managed identity of Foundry project '${project_name}'." >&2
		return 1
	fi
	if [[ -z "${project_principal_id}" ]]; then
		echo "Foundry project '${project_name}' does not expose a system-assigned managed identity." >&2
		return 1
	fi

	assign_role_if_missing "${project_principal_id}" "ba92f5b4-2d11-453d-a403-e96b0029c9fe" "${storage_resource_id}" "Storage Blob Data Contributor" || return 1
	assign_role_if_missing "${project_principal_id}" "230815da-be43-4aae-9cb4-875f7bd000aa" "${cosmosdb_resource_id}" "Cosmos DB Operator" || return 1
	assign_role_if_missing "${project_principal_id}" "8ebe5a00-799e-43f5-93ac-243d3dce84a7" "${search_resource_id}" "Search Index Data Contributor" || return 1
	assign_role_if_missing "${project_principal_id}" "7ca78c08-252a-4471-8644-bb5ff32d4ba0" "${search_resource_id}" "Search Service Contributor" || return 1

	echo "Creating or updating project connection '${STORAGE_ACCOUNT_NAME}'..."
	az rest --method put --url "${storage_connection_url}" --body "{\"properties\":{\"category\":\"AzureStorageAccount\",\"target\":\"https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/\",\"authType\":\"AAD\",\"metadata\":{\"ApiType\":\"Azure\",\"ResourceId\":\"${storage_resource_id}\",\"location\":\"${location}\"}}}" --only-show-errors --output none || return 1
	wait_for_foundry_resource_succeeded "${storage_connection_url}" "project connection '${STORAGE_ACCOUNT_NAME}'" || return 1

	echo "Creating or updating project connection '${SEARCH_SERVICE_NAME}'..."
	az rest --method put --url "${search_connection_url}" --body "{\"properties\":{\"category\":\"CognitiveSearch\",\"target\":\"https://${SEARCH_SERVICE_NAME}.search.windows.net\",\"authType\":\"AAD\",\"metadata\":{\"ApiType\":\"Azure\",\"ResourceId\":\"${search_resource_id}\",\"location\":\"${location}\"}}}" --only-show-errors --output none || return 1
	wait_for_foundry_resource_succeeded "${search_connection_url}" "project connection '${SEARCH_SERVICE_NAME}'" || return 1

	echo "Creating or updating project connection '${COSMOSDB_SERVICE_NAME}'..."
	az rest --method put --url "${cosmosdb_connection_url}" --body "{\"properties\":{\"category\":\"CosmosDB\",\"target\":\"https://${COSMOSDB_SERVICE_NAME}.documents.azure.com:443/\",\"authType\":\"AAD\",\"metadata\":{\"ApiType\":\"Azure\",\"ResourceId\":\"${cosmosdb_resource_id}\",\"location\":\"${location}\"}}}" --only-show-errors --output none || return 1
	wait_for_foundry_resource_succeeded "${cosmosdb_connection_url}" "project connection '${COSMOSDB_SERVICE_NAME}'" || return 1

	echo "Creating project capability host '${FOUNDRY_CAPABILITY_HOST_NAME}' with customer-owned data services..."
	if ! az rest \
		--method put \
		--url "${project_capability_host_url}" \
		--body "{\"properties\":{\"capabilityHostKind\":\"Agents\",\"threadStorageConnections\":[\"${COSMOSDB_SERVICE_NAME}\"],\"vectorStoreConnections\":[\"${SEARCH_SERVICE_NAME}\"],\"storageConnections\":[\"${STORAGE_ACCOUNT_NAME}\"]}}" \
		--only-show-errors \
		--output none; then
		echo "Failed to create the project capability host." >&2
		return 1
	fi
	wait_for_foundry_resource_succeeded "${project_capability_host_url}" "project capability host '${FOUNDRY_CAPABILITY_HOST_NAME}'" || return 1

	echo "Microsoft Foundry Standard Agent Setup '${service_name}/${project_name}' created successfully."
}


create_resource_group_if_missing "${NETWORKING_RG}"
create_resource_group_if_missing "${FOUNDRY_RG}"
create_resource_group_if_missing "${RESOURCES_RG}"
create_resource_group_if_missing "${DNS_RG}"
create_resource_group_if_missing "${JUMPVM_RG}"

create_vnet_if_missing "${VNET_NAME}" "${NETWORKING_RG}" "${VNET_ADDRESS_PREFIX}"
create_subnet_if_missing "${VNET_NAME}" "${FOUNDRY_SUBNET_NAME}" "${FOUNDRY_SUBNET_PREFIX}" "${NETWORKING_RG}" "${COGNITIVE_SERVICES_SERVICE_ENDPOINT}" ""
create_subnet_if_missing "${VNET_NAME}" "${RESOURCES_SUBNET_NAME}" "${RESOURCES_SUBNET_PREFIX}" "${NETWORKING_RG}" "" ""
# The injected Agent runtime requires explicit outbound access unless a NAT gateway or UDR/firewall is attached.
create_subnet_if_missing "${VNET_NAME}" "${AGENTS_DELEGATED_SUBNET_NAME}" "${AGENTS_DELEGATED_SUBNET_PREFIX}" "${NETWORKING_RG}" "" "${CONTAINER_APPS_SUBNET_DELEGATION}" true
create_subnet_if_missing "${VNET_NAME}" "${PE_SUBNET_NAME}" "${PE_SUBNET_PREFIX}" "${NETWORKING_RG}" "" ""
create_subnet_if_missing "${VNET_NAME}" "${JUMP_SUBNET_NAME}" "${JUMP_SUBNET_PREFIX}" "${NETWORKING_RG}" "" ""

create_storage_account_if_missing "${STORAGE_ACCOUNT_NAME}" "${RESOURCES_RG}"
create_aisearch_if_missing "${SEARCH_SERVICE_NAME}" "${RESOURCES_RG}"
create_cosmosdb_if_missing "${COSMOSDB_SERVICE_NAME}" "${RESOURCES_RG}" "${LOCATION}"
create_foundry_if_missing "${FOUNDRY_SERVICE_NAME}" "${FOUNDRY_RG}" "${LOCATION}" "${FOUNDRY_PROJECT_NAME}"

# Storage Account - Private Endpoint
STORAGE_RESOURCE_ID="/subscriptions/${SUBID}/resourceGroups/${RESOURCES_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}"
create_private_endpoint_if_missing "${NETWORKING_RG}" "${STORAGE_RESOURCE_ID}" "${STORAGE_PRIVATE_DNS_SUB_TARGET}" "dynamic" "${STORAGE_PRIVATE_ENDPOINT_NAME}" "${VNET_NAME}" "${PE_SUBNET_NAME}" "${NETWORKING_RG}"
AddDnsZoneConfiguration "${SUBID}" "${DNS_RG}" "${STORAGE_PRIVATE_DNS_SUB_TARGET}" "${STORAGE_PRIVATE_DNS_ZONE}" "${NETWORKING_RG}" "${STORAGE_PRIVATE_ENDPOINT_NAME}"
create_private_dns_vnet_link_if_missing "${SUBID}" "${DNS_RG}" "${STORAGE_PRIVATE_DNS_ZONE}" "${VNET_RESOURCE_ID}" "${STORAGE_PRIVATE_DNS_VNET_LINK_NAME}"

# Azure AI Search - Private Endpoint
create_private_endpoint_if_missing "${NETWORKING_RG}" "${SEARCH_RESOURCE_ID}" "${SEARCH_PRIVATE_DNS_SUB_TARGET}" "dynamic" "${SEARCH_PRIVATE_ENDPOINT_NAME}" "${VNET_NAME}" "${PE_SUBNET_NAME}" "${NETWORKING_RG}"
AddDnsZoneConfiguration "${SUBID}" "${DNS_RG}" "${SEARCH_PRIVATE_DNS_SUB_TARGET}" "${SEARCH_PRIVATE_DNS_ZONE}" "${NETWORKING_RG}" "${SEARCH_PRIVATE_ENDPOINT_NAME}"
create_private_dns_vnet_link_if_missing "${SUBID}" "${DNS_RG}" "${SEARCH_PRIVATE_DNS_ZONE}" "${VNET_RESOURCE_ID}" "${SEARCH_PRIVATE_DNS_VNET_LINK_NAME}"

# Azure CosmosDB - Private Endpoint
create_private_endpoint_if_missing "${NETWORKING_RG}" "${COSMOSDB_RESOURCE_ID}" "${COSMOSDB_PRIVATE_DNS_SUB_TARGET}" "dynamic" "${COSMOSDB_PRIVATE_ENDPOINT_NAME}" "${VNET_NAME}" "${PE_SUBNET_NAME}" "${NETWORKING_RG}"
AddDnsZoneConfiguration "${SUBID}" "${DNS_RG}" "${COSMOSDB_PRIVATE_DNS_SUB_TARGET}" "${COSMOSDB_PRIVATE_DNS_ZONE}" "${NETWORKING_RG}" "${COSMOSDB_PRIVATE_ENDPOINT_NAME}"
create_private_dns_vnet_link_if_missing "${SUBID}" "${DNS_RG}" "${COSMOSDB_PRIVATE_DNS_ZONE}" "${VNET_RESOURCE_ID}" "${COSMOSDB_PRIVATE_DNS_VNET_LINK_NAME}"

# Azure Foundry - Private Endpoint
create_private_endpoint_if_missing "${NETWORKING_RG}" "${FOUNDRY_RESOURCE_ID}" "${FOUNDRY_PRIVATE_DNS_SUB_TARGET}" "dynamic" "${FOUNDRY_PRIVATE_ENDPOINT_NAME}" "${VNET_NAME}" "${PE_SUBNET_NAME}" "${NETWORKING_RG}"
AddDnsZoneConfiguration "${SUBID}" "${DNS_RG}" "${FOUNDRY_PRIVATE_DNS_SUB_TARGET}" "${FOUNDRY_COGNITIVE_PRIVATE_DNS_ZONE}" "${NETWORKING_RG}" "${FOUNDRY_PRIVATE_ENDPOINT_NAME}" "default" "privatelink_cognitiveservices_azure_com"
AddDnsZoneConfiguration "${SUBID}" "${DNS_RG}" "${FOUNDRY_PRIVATE_DNS_SUB_TARGET}" "${FOUNDRY_OPENAI_PRIVATE_DNS_ZONE}" "${NETWORKING_RG}" "${FOUNDRY_PRIVATE_ENDPOINT_NAME}" "default" "privatelink_openai_azure_com"
AddDnsZoneConfiguration "${SUBID}" "${DNS_RG}" "${FOUNDRY_PRIVATE_DNS_SUB_TARGET}" "${FOUNDRY_SERVICES_PRIVATE_DNS_ZONE}" "${NETWORKING_RG}" "${FOUNDRY_PRIVATE_ENDPOINT_NAME}" "default" "privatelink_services_ai_azure_com"
create_private_dns_vnet_link_if_missing "${SUBID}" "${DNS_RG}" "${FOUNDRY_COGNITIVE_PRIVATE_DNS_ZONE}" "${VNET_RESOURCE_ID}" "${FOUNDRY_COGNITIVE_DNS_VNET_LINK_NAME}"
create_private_dns_vnet_link_if_missing "${SUBID}" "${DNS_RG}" "${FOUNDRY_OPENAI_PRIVATE_DNS_ZONE}" "${VNET_RESOURCE_ID}" "${FOUNDRY_OPENAI_DNS_VNET_LINK_NAME}"
create_private_dns_vnet_link_if_missing "${SUBID}" "${DNS_RG}" "${FOUNDRY_SERVICES_PRIVATE_DNS_ZONE}" "${VNET_RESOURCE_ID}" "${FOUNDRY_SERVICES_DNS_VNET_LINK_NAME}"

### Run only after all four private endpoints and Foundry VNet injection are ready.
disable_public_network_access_if_private_ready

read -rsp "Jump VM password: " JUMPVM_PASSWORD && echo
create_jumpvm "${JUMPVM_NAME}" "${JUMPVM_RG}" "${VNET_NAME}" "${JUMP_SUBNET_NAME}" "${LOCATION}" "${JUMPVM_USERNAME}" "${JUMPVM_PASSWORD}"
unset JUMPVM_PASSWORD