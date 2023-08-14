# dns_latency
Measure DNS latency with only BASH and TCPDUMP

The script is to measure DNS response latency from multiple remote providers and local.
It uses TCPDUMP timestamps with microsecond fractional resolution, then capture the traffic while issuing 3 nslookup query per provider, discard the first nslookup which is usually higher because DNS cache might not exist yet, and finally calculate the average.

Basically, script will match 2 lines and calculate the time difference based on the timestamps.
