#!/bin/sh

#
# Check that jq is installed
#
command -v jq >/dev/null 2>&1 || { logger -s "cf_ddns" "[WARNING] jq is required for JSON parsing. Please install. Aborting."; exit 1; }

#
# Define the following variables, or leave as default where filled in
#
#######################################################################################
# VARIABLES TO CHANGE                                                                 #
cf_api_key=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx	                              # CloudFlare token#
zid=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx				# Cloudflare Zone ID              #
email=email@domain.com								# Cloudflare login account        #
domain=sub.domain.com			            		# Domain Name you wish to update  #
#######################################################################################
# DEFAULTS                                                                            #
type=A			 									# CloudFlare Record Type	      #
ttl=1												# TTL value					      #
#######################################################################################

#
# Grab current IP
#
check_site=$(curl -s -o /dev/null -w "%{http_code}" ifconfig.co/ip)

# Check if the DNS update succeeded or failed
if [ "$check_site" = "200" ]; then
	current_ip=$(curl -s ifconfig.co/ip)
else
	logger -s "cf_ddns" "[WARNING] Could not obtain IP address. Aborting."
	exit 1
fi


#######################
# Start of functions  #
#######################
#
# Find all the current domains in the zone, and compress the results
#
function check_existing {
	#
	# Grab all the entries of the same record type
	#
	logger -s "cf_ddns" "[INFO] Pulling all DNS entries of type $type"
	list_all=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zid/dns_records?type=$type" -H "X-Auth-Email: $email" -H "X-Auth-Key: $cf_api_key" -H "Content-Type: application/json" | jq -c '.result[] | {domain: .name, zone_id: .id, ip: .content}')

	#
	# Loop through and find if the domain exists
	#
	dom_exists=false
	for row in ${list_all} ;do
		loop_dom=$(echo $row | jq -r '.domain')
		loop_zone=$(echo $row | jq -r '.zone_id')
		loop_ip=$(echo $row | jq -r '.ip')
		if [ "$loop_dom" = "$domain" ]; then
			dom_exists=true # Domin has been located
			break
		fi
	done

}

#
# If is is not found, there should be a DNS made for it 
#
function create_dns {
	logger -s "cf_ddns" "[INFO] Domain has not been located and is being created ..."

	create_result=$(curl -s -X POST https://api.cloudflare.com/client/v4/zones/$zid/dns_records \
	-H "X-Auth-Email: $email" \
	-H "X-Auth-Key: $cf_api_key" \
	-H "Content-Type: application/json" \
	--data '{"type":"'$type'","name":"'$domain'","content":"'$current_ip'","ttl":"'$ttl'","proxied":true}' | jq '.success')
}

#
# Update the IP address of the DNS
#
function update_dns {
	logger -s "cf_ddns" "[NOTICE] IP change detected! Old: "$loop_ip" - New: "$current_ip 
	update_result=$(curl -s -X PUT https://api.cloudflare.com/client/v4/zones/$zid/dns_records/$loop_zone \
		-H "X-Auth-Email: $email" \
		-H "X-Auth-Key: $cf_api_key" \
		-H "Content-Type: application/json" \
		--data '{"type":"'$type'","name":"'$domain'","content":"'$current_ip'","proxied":true}' | jq '.success')
}

#######################
# Start of main code  #
#######################
check_existing # Call the check all exiting DNS option 

#
# Check if the result comes back found
#
if [ "$dom_exists" = "true" ]; then
	logger -s "cf_ddns" "[INFO] Domain has been located. Comparing current and upstream IP."
	# now compare current IP to upstream recorded IP
	if [ "$current_ip" = "$loop_ip" ]; then
		logger -s "cf_ddns" "[INFO] IP adress is the same. No action is being taken."
	else
		update_dns # Call update DNS function

		#
		# Check if the DNS update succeeded or failed
		#
		if [ "$update_result" = "true" ]; then
			logger -s "cf_ddns" "[INFO] Domain was updated successfully."
		else
			logger -s "cf_ddns" "[WARNING] Domain updating failed."
			exit 1
		fi
	fi
else
	create_dns # Call the create DNS function

	#
	# Check if the DNS creation succeeded or failed
	#
	if [ "$create_result" = "true" ]; then
		logger -s "cf_ddns" "[INFO] Domain was created successfully."
	else
		logger -s "cf_ddns" "[WARNING] Domain creation failed."
		exit 1
	fi
fi

exit 0	
