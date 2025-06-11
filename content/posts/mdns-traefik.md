---
title: Docker mDNS Publisher
description: Automatically publish Docker container hostnames using mDNS (Avahi)
summary: |
  Learn how to automatically publish Docker container hostnames as mDNS records using Avahi,
  making your Traefik-managed services discoverable on your local network without manual DNS configuration.
date: 2025-06-11T10:15:00+01:00
draft: false
toc: false
images:
keywords:
  - docker
  - avahi
  - mdns
  - traefik
  - dns
  - service discovery
slug: mdns-traefik
tags:
  - docker
  - networking
  - traefik
categories:
  - Provisioning and orchestration
---

## TL;DR

If you're using Traefik with Docker and want to make your services discoverable on your local network without configuring DNS servers, you can use this script to automatically publish mDNS records:

{{< gist mortezaPRK ca53a3863b5c0b34ce2dc71e2ef8d31e mdns-publisher.sh >}}

This final version:
1. Monitors Docker events for container changes
2. Extracts hostnames from Traefik labels
3. Uses an associative array to efficiently track and manage mDNS publishers
4. Only updates records that actually change

But the journey to get there was interesting! Read on to see how I built this solution step by step.

## The Problem

I run several services at home using Docker containers with Traefik as a reverse proxy. While Traefik handles the routing based on hostnames, I still needed a way for devices on my network to discover these hostnames without:

1. Maintaining a local DNS server
2. Manually editing `/etc/hosts` files on each device
3. Using custom ports for each service

I needed a solution that would automatically maintain DNS records for my services as containers are started or stopped.

## Enter mDNS with Avahi

mDNS (multicast DNS) is perfect for local network service discovery. It's the technology behind Bonjour/Zeroconf that lets you access devices with `.local` domains.

Avahi is the Linux implementation of mDNS, and it provides tools like `avahi-publish` that can dynamically announce hostnames on your network.

## The Solution: An Evolutionary Approach

I took an iterative approach to solving this problem, starting with a simple solution and improving it as I learned more.

### Iteration 1: The Basic Script

My first attempt was simple but effective. I wrote a script that:

1. Gets a list of hostnames from Traefik's router rules in running containers
2. Publishes these hostnames as mDNS records using Avahi
3. Tracks the PIDs of the publisher processes in a simple array

Here's the core of that initial approach:

```bash
#!/bin/bash

IP=$(hostname -I | awk '{print $1}')
PUBLISHERS=()  # Just a simple array for PIDs

function get_hostnames() {
  docker inspect $(docker ps -q) 2>/dev/null \
    | jq -r '.[].Config.Labels 
              | to_entries[]? 
              | select(.key | test("^traefik\\.http\\.routers\\..*\\.rule$")) 
              | .value' \
    | grep -oE 'Host\(`[^`]+`\)' \
    | sed -E 's/Host\(`([^`]+)`\)/\1/' \
    | sort -u
}

function refresh_publishers() {
  # Kill all existing publishers
  for pid in "${PUBLISHERS[@]}"; do
    kill "$pid" 2>/dev/null
  done
  PUBLISHERS=()
  
  # Start new publishers for all hostnames
  local hostnames=($(get_hostnames))
  for hostname in "${hostnames[@]}"; do
    echo "Starting mDNS for $hostname -> $IP"
    avahi-publish -a "$hostname" -R "$IP" &
    PUBLISHERS+=($!)
  done
}

# Initial setup
refresh_publishers

# Keep the script running
while true; do
  sleep 60
  refresh_publishers
done
```

This worked! Every minute, it would kill all the existing publishers and create new ones based on the current set of containers. But it had several issues:

1. It polled every 60 seconds rather than responding to events
2. It killed and recreated ALL publishers even when only one container changed
3. It didn't handle script termination gracefully

### Iteration 2: Event-Driven Updates

Next, I improved the script to watch Docker events instead of polling:

```bash
function docker_event_watcher() {
  docker events --filter 'event=start' --filter 'event=stop' --filter 'event=die' --filter 'event=destroy' |
  while read -r event; do
    echo "Docker event: $event"
    # Still using the inefficient approach of refreshing everything
    refresh_publishers
  done
}

# Replace the polling loop with an event watcher
docker_event_watcher
```

This was already better - now the script would update the mDNS records immediately when containers were started or stopped. But I quickly noticed that during system shutdown or Docker restarts, multiple events would fire rapidly.

### Iteration 3: Adding a Sleep Timer

To prevent the script from thrashing when multiple events occur in quick succession, I added a simple sleep timer:

```bash
function docker_event_watcher() {
  docker events --filter 'event=start' --filter 'event=stop' --filter 'event=die' --filter 'event=destroy' |
  while read -r event; do
    echo "Docker event: $event"
    sleep 1  # <-- Critical addition!
    refresh_publishers
  done
}
```

The `sleep 1` is critical here. When the system is shutting down or Docker is restarting, multiple containers might stop in quick succession. Without the sleep timer, the script might try to refresh publishers too rapidly, potentially causing resource contention issues. The sleep ensures that we batch these events together and only refresh the publishers once things have settled.

### Iteration 4: Efficient Publisher Management with Associative Arrays

As I began to use this script in production, I realized the approach was inefficient. For a long-lived process, killing and recreating all publishers whenever any container changed wasn't ideal. So I refactored the code to use an associative array that would track which hostname was published by which process:

```bash
# More efficient approach using associative arrays
declare -A PUBLISHERS  # hostname -> PID

function start_publisher() {
  local hostname="$1"
  echo "Starting mDNS for $hostname -> $IP"
  avahi-publish -a "$hostname" -R "$IP" &
  PUBLISHERS["$hostname"]=$!
}

function stop_publisher() {
  local hostname="$1"
  local pid="${PUBLISHERS[$hostname]}"
  if [[ -n "$pid" ]]; then
    echo "Stopping mDNS for $hostname (PID $pid)"
    kill "$pid" 2>/dev/null
    unset PUBLISHERS["$hostname"]
  fi
}

function refresh_publishers() {
  local new_hostnames=($(get_hostnames))
  local current_hostnames=("${!PUBLISHERS[@]}")
  local to_add=()
  local to_remove=()

  # Determine what to add
  for h in "${new_hostnames[@]}"; do
    [[ -z "${PUBLISHERS[$h]}" ]] && to_add+=("$h")
  done

  # Determine what to remove
  for h in "${current_hostnames[@]}"; do
    if ! [[ " ${new_hostnames[*]} " =~ " $h " ]]; then
      to_remove+=("$h")
    fi
  done

  for h in "${to_remove[@]}"; do stop_publisher "$h"; done
  for h in "${to_add[@]}"; do start_publisher "$h"; done
}
```

With this approach, the script only starts or stops publishers for hostnames that have actually changed. This is much more efficient and reduces network traffic from unnecessary mDNS announcements.

### Iteration 5: Proper Cleanup on Exit

Finally, I added proper cleanup handling to ensure all publisher processes were terminated when the script was stopped:

```bash
function cleanup() {
  echo "Cleaning up mDNS publishers..."
  for h in "${!PUBLISHERS[@]}"; do
    stop_publisher "$h"
  done
  if [[ "$WATCHER_PID" -gt 0 ]]; then
    kill "$WATCHER_PID" 2>/dev/null
  fi
  exit 0
}

trap cleanup SIGINT SIGTERM
```

## The Final Solution

After several iterations, the final script puts all these components together for a robust, efficient solution:

1. Uses associative arrays to track publishers by hostname
2. Responds to Docker events in real-time
3. Handles batches of events with a sleep timer
4. Cleans up properly when terminated

Here's how the event watcher and main script execution looks in the final version:

```bash
function docker_event_watcher() {
  docker events --filter 'event=start' --filter 'event=stop' --filter 'event=die' --filter 'event=destroy' |
  while read -r event; do
    echo "Docker event: $event"
    sleep 1  # Critical to batch rapid events together
    refresh_publishers
  done
}

# Main script execution
IP=$(hostname -I | awk '{print $1}')
declare -A PUBLISHERS  # hostname -> PID
WATCHER_PID=0

trap cleanup SIGINT SIGTERM

# Initial setup of publishers
refresh_publishers

# Start the event watcher in the background
docker_event_watcher &
WATCHER_PID=$!

# Wait on docker watcher only
wait "$WATCHER_PID"
```

This approach results in a resilient script that efficiently manages mDNS records for Docker containers running behind Traefik.

## Running as a Service

For reliability, you should run this as a systemd service. Create a file at `/etc/systemd/system/mdns-publisher.service`:

```ini
[Unit]
Description=Dynamic mDNS publisher for Docker-hosted services
After=network.target avahi-daemon.service
Requires=avahi-daemon.service
PartOf=avahi-daemon.service
BindsTo=avahi-daemon.service

[Service]
Type=simple
ExecStart=/opt/mdns-publisher/mdns-publisher.sh
Restart=on-failure
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
```

Then enable and start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now mdns-publisher.service
```

## Benefits

With this solution:

1. All your Traefik-managed services are automatically discoverable on the local network
2. No need to manage DNS servers or edit hosts files
3. When containers are added/removed, DNS records update automatically
4. Works across different devices and operating systems that support mDNS

## Prerequisites

- Docker
- Avahi (install with `apt-get install avahi-utils` on Ubuntu/Debian)
- jq (for JSON parsing)
- Traefik with Docker provider

---

Now all my Docker services are automatically discoverable on my home network without any additional configuration on client devices. Let me know if you find this useful or have ideas for improvements!

> Note: An alternative to pulling hostnames from Traefik labels is to use define a static list of hostnames (after all, normal people rarely create new containers every day). You can then use a simple array in the script to manage those hostnames instead of pulling them dynamically from Docker (or even getting them from the `compose.yml` files using `yq`). This would simplify the script further, but I prefer the dynamic approach for flexibility.
