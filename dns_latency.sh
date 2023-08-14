#!/bin/sh

#####################################################################################################################
# The script is to measure DNS response latency from multiple remote providers and local.
# It uses TCPDUMP timestamps with microsecond fractional resolution,
# then capture the traffic while issuing 3 nslookup query per provider, discard first nslookup which is
# usually higher because DNS cache might not exist yet,
# and finally calculate the average.
#
# Basically script will match 2 lines and calculate the time difference based
# on the timestamps.
#####################################################################################################################

# Setup
# Host to check
HOST=adriangiacometti.net
# Protocol udp, tcp, icmp
PROTOCOL=udp
# Port number
PORT=53
# Test numbers - First test will be discarded as it usually populates caches along the way
TEST_TIMES=4
# User running this script
USERNAME=$(id -un)

echo "-- Host to check: $HOST"
echo "   Protocol: $PROTOCOL"
echo "   Port: $PORT"

# IP of Local Default Gateway, this works for home settings where usually your home router is your local DNS or forwarder
DEFAULT_ROUTE=$(ip route | awk '/default/ { print $3 }')

# Define the DNS providers with their names and IPs
# Cloudflare-Block to Cloudflare Family service. It adds DNS resolution block for Malware and Adult content.
# It is a bit slower (milliseconds anyway) but the benefit makes it worthy.
set -- "Local_Default_Gateway $DEFAULT_ROUTE" "Google 8.8.8.8" "Cloudflare 1.1.1.1" "Cloudflare-Block 1.1.1.3" "OpenDNS 208.67.222.222"

# Save terminal settings as it breaks after tcpdump
CURRENT_TERMINAL_SETTINGS=$(stty -g)

# Iterate over the DNS providers
for provider do
  # Split the provider string into name and IP
  provider_name=${provider% *}
  provider_ip=${provider#* }

  # Total time to calculate average later
  total_time=0

  # Provider to use in the test
  echo
  echo "-- Provider: $provider_name"
  echo "-- Provider IP: $provider_ip"
  echo

  while [ $i -le $TEST_TIMES ]; do
    if [ $i -eq 1 ]
    then
      echo "- Test $i - Discarding this first test from the computation"
    else
      echo "- Test $i"
    fi

    # Get the current time and date for file naming
    date=$(date +%Y%m%d%H%M%S)

    # Name the pcap file with the current timestamp
    tcpdump_file="tcpdump_$date.txt"
    # echo -e "\n$tcpdump_file"

    # Start tcpdump in the background, capturing packets
    sudo tcpdump -n host "$provider_ip" and $PROTOCOL port $PORT > "$tcpdump_file" 2>&1 &

    # Save the PID of tcpdump to kill it later
    tcpdump_PID=$!

    # Allow tcpdump to start up
    sleep 5

    # Execute the nslookup command and suppress its output
    response=$(nslookup "$HOST" "$provider_ip")
    # echo "DNS Response: $response"

    # Sleep for a bit to allow the response packet to be captured
    sleep 1

    # Stop tcpdump if nothing captured
    sudo kill -9 $tcpdump_PID

    # Change ownership of the file if this script was executed with sudo
    # shellcheck disable=SC2086
    sudo chown $USERNAME:$USERNAME "$tcpdump_file"

    # Sleep to give time to write to file
    sleep 1

    # Analyze the capture to identify the lines to process

    #####################################################################################
    #####################################################################################
    # FROM HERE
    # Modify this block to match the tcpdump output for other protocols and ports

    # cat $tcpdump_file

    # Extract the line with the request
    line_1=$(grep -m 1 "+.*$HOST" "$tcpdump_file")

    # Extract the number from the first line
    dns_req_number=$(echo $line_1 | awk -F' ' '{print $6}' | awk -F'+' '{print $1}')

    # Extract the second line with the same number as it will be the reply
    line_2=$(grep -m 2 "$dns_req_number" "$tcpdump_file" | sed -n '2p')
    # TO HERE
    #####################################################################################
    #####################################################################################

    # Re-apply terminal settings
    stty "$CURRENT_TERMINAL_SETTINGS"

    # Print matched lines
    echo "  Query packet: $line_1"
    echo "  Reply packet: $line_2"

    # We find the first and the last packets and get the timestamp difference
    # Calculate the duration using awk to handle fractional seconds
    # Multiply by 1000 to convert seconds to milliseconds
    start_time_hour=$(echo $line_1 | awk -F'[:.]' '{print $1}')
    start_time_minute=$(echo $line_1 | awk -F'[:.]' '{print $2}')
    start_time_seconds=$(echo $line_1 | awk -F'[:.]' '{print $3}')
    start_time_micro=$(echo $line_1 | awk -F'[:.]' '{print $4}')
    start_time_total=$(awk -v h="$start_time_hour" -v m="$start_time_minute" -v s="$start_time_seconds" -v micro="$start_time_micro" 'BEGIN { print h * 60 * 60 * 1000000 + m * 60 * 1000000 + s * 1000000 + micro }')
    
    end_time_hour=$(echo $line_2 | awk -F'[:.]' '{print $1}')
    end_time_minute=$(echo $line_2 | awk -F'[:.]' '{print $2}')
    end_time_seconds=$(echo $line_2 | awk -F'[:.]' '{print $3}')
    end_time_micro=$(echo $line_2 | awk -F'[:.]' '{print $4}')
    end_time_total=$(awk -v h="$end_time_hour" -v m="$end_time_minute" -v s="$end_time_seconds" -v micro="$end_time_micro" 'BEGIN { print h * 60 * 60 * 1000000 + m * 60 * 1000000 + s * 1000000 + micro }')

    duration=$(awk -v start="$start_time_total" -v end="$end_time_total" 'BEGIN { printf "%f\n", (end - start) / 1000 }')

    echo "  Response time is: $duration milliseconds"

    # Remove the pcap file
    rm "$tcpdump_file"

    # Add to the total time
    if [ $i -gt 1 ]
    then
      total_time=$(awk -v total="$total_time" -v duration="$duration" 'BEGIN { print total + duration }')
    fi

    i=$((i + 1))
  
  done

  # Calculate and print the average time
  average=$(awk -v total="$total_time" -v count="$i" 'BEGIN { print total / (count-2) }')
  echo
  echo "==> Average $provider_name response time: $average milliseconds"

done