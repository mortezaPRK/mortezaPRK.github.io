---
title: Dockhand
description: Restarding unhealthy docker containers
summary: |
  If you have bunch od docker containers that go unhealthy and you want to restart them automatically, you have
  two options: either use deunhealth or use a simple bash script to do the same thing.
date: 2024-12-26T07:47:40+01:00
draft: false
toc: false
images:
keywords:
  - docker
  - healthcheck
slug: dockhand
tags:
  - docker
categories:
  - Provisioning and orchestration
---

## TL;DR

Either use [deunhealth](https://github.com/qdm12/deunhealth) or run this bash script:

{{< gist mortezaPRK db9f82fabcb4b5c441c89ab80e02a670 dockhand.sh >}}

Now any container that has the label `autoheal=true` will be restarted when it goes unhealthy.


## The problem

I have bunch of docker containers running here and there. Sometimes, they go unhealthy and I have to restart them. But I don't want to do this manually. I want to automate this process.

At first, I thought there should already be a way to do this and I found this niche tool called [deunhealth](https://github.com/qdm12/deunhealth).

It was easy to install and use. All I had to do was to give access to the docker socket and add a specific label to the containers that I want to monitor.


> [!CAUTION]
> **Giving access to the docker socket is a security risk!**

I'm paranoid about security and I don't want to give access to the docker socket to any random tool. No hard feelings, deunhealth :melting_face:

> [!NOTE]
> The reason is, I don't want to review every line of code in the tool to make sure it's not doing anything malicious, let alone checking every release and dependency!


## The solution

So what are my options?

1. Don't be paranoid and use deunhealth (You can do this if you trust the tool, or you're a normal person)
2. Write a simple script that does the same thing in Go or Python (since Docker has SDKs for these languages)
3. Write a bash script that does the same thing


For me, the first option is out of the question.

The second option was easy to implement. Checking the [docker-py documentation](https://docker-py.readthedocs.io/en/stable/client.html), There is a method to listen to events:

```python
# pip install docker
import docker

client = docker.from_env()
for event in client.events(decode=True):
    print(event)
```

But this would print all events. I only want the events that:
1. Are related to `health` of the container, preferably narrowed down to `unhealthy` status
2. Are related to the containers only (not images, networks, etc.)
3. Only emited for the containers that have a specific label (e.g. `autoheal=true`)

### Jumping into the rabbit hole

How can I test these filters? Docker cli already has a command to listen to the events: `docker system events`.

Next, I want to run a container with a specific label and a simple healthcheck command to be able to see the events.

```shell
docker run --rm \
    --name autohealtest \
    --label 'autoheal=true' \  # The label that I want to filter the events with
    --health-cmd='test ! -f /tmp/hc || exit 1' \  # The healthcheck. It will fail if /tmp/hc exists
    --health-interval=10s \
    --health-timeout=1s \
    --health-retries=3 \
    alpine:latest tail -f /dev/null  # The command that will keep the container running forever
```

In another terminal, I run the docker events command:

```shell
docker system events --format json

# Output:
# {
#     "status": "create",
#     "id": "9721b76dba119e3d778a5d62dca8f0329b4a3306672da19e4048f2c31e7e3f11",
#     "from": "alpine:latest",
#     "Type": "container",
#     "Action": "create",
#     "Actor": {
#         "ID": "9721b76dba119e3d778a5d62dca8f0329b4a3306672da19e4048f2c31e7e3f11",
#         "Attributes": {
#             "autoheal": "true",
#             "image": "alpine:latest",
#             "name": "autohealtest"
#         }
#     },
#     "scope": "local",
#     "time": 1735191091,
#     "timeNano": 1735191091153980331
# }
```

Now let's [filter the events](https://docs.docker.com/reference/cli/docker/system/events/#filter) by:
1. Type: container
2. Label: autoheal=true
3. Health status: unhealthy

```shell
docker system events \
    --filter type=container \  # Only container events
    --filter label=autoheal=true \  # Only the containers with the label autoheal=true
    --filter event='health_status: unhealthy' \ # Only the unhealthy containers
    --format json
```

Now if I create a file in the `autohealtest` container under `/tmp/hc`, the healthcheck will fail and the container will be marked as unhealthy.

```shell
docker exec autohealtest touch /tmp/hc
```

And I see the event in my terminal:
```json
{
    "status": "health_status: unhealthy",
    "id": "19ccabc70b9011ad4ca4b67eb1b335ac3523d0b1174d238599a132085fdcb142",
    "from": "alpine:latest",
    "Type": "container",
    "Action": "health_status: unhealthy",
    "Actor": {
        "ID": "19ccabc70b9011ad4ca4b67eb1b335ac3523d0b1174d238599a132085fdcb142",
        "Attributes": {
            "autoheal": "true",
            "image": "alpine:latest",
            "name": "autohealtest"
        }
    },
    "scope": "local",
    "time": 1735191438,
    "timeNano": 1735191438145468746
}
```

### Back to Python

Now that I know the filters, I can implement the Python script:

```python
# pip install docker
import docker

client = docker.from_env()
for event in client.events(
  filters={
    'type': 'container',
    'label': 'autoheal=true',
    'event': 'health_status: unhealthy'
  },
  decode=True
):
    client.containers.get(event['id']).restart()
```

That's it!

### The bash script

As you already saw in the previous section, during this investigation I accidentally wrote the third option.

A bash script that does the same thing + a systemd service to run it.

{{< gist mortezaPRK db9f82fabcb4b5c441c89ab80e02a670 >}}


## What's next?

1. Blindly restarting the containers might be ok for simple scenarios, but I might need to add some checks to make sure the container is really unhealthy before restarting it, and maybe add a jitter before restarting several containers at the same time to avoid thundering herd problem.
2. This can definitely be a good candidate for the next Docker or Compose feature. I'll open an issue on their GitHub (probably someone already did, I should've check that first :sweat_smile:)
3. I heard about Docker plugins. Last time I checked, there was no way to manipulate containers, but I'll check again.
