# Jitsi Meet on Docker

Jitsi is a set of Open Source projects that allows you to easily build and deploy secure
videoconferencing solutions.

[Jitsi Meet] is a fully encrypted, 100% Open Source videoconferencing solution that you can use
all day, every day, for free — with no account needed.

This repository contains the necessary tools to run a Jitsi Meet stack on Docker using
Docker Compose.

## Table of contents

* [Prosody](#prosody)
* [Setup](#setup)
* [Jibri](#jibri)

<hr />

## Prosody

Prosody is the authentication service used by Jitsi Meet.
It is very customizable as it supports addition of custom prosody modules

The following modules have been added:

### mod_token_moderation

By default, prosody allows any user with a valid JSON token to join as a moderator.
This mod lets us control who gets to be the moderator. It works by adding the boolean
value 'moderator' to the token payload.

### mod_token_verification

Prosody does not check for uniqueness in token, so two people with the same token can
connect to a Jitsi conference. This gets the email of all the participants in the room,
if the email of the joining participant matches with that of an already connected
participant, then the joining participant is kicked out.

### mod_muc_size

This mod advertises routes to the BOSH port of prosody. Two new routes have been added
in this module.

* participants-list : Lists out all participants along with their role in a room
* shutdown-room : Terminates the session

## Setup

Clone this repository and rename env.example to .env
> git clone <git_url> jitsi-meet

cd inside the folder
> cd jitsi-meet

Run make to build images locally
> make

Start the project using docker-compose up
> docker-compose up -d

To stop the containers, run
> docker-compose down

Ensure to delete the config folder, usually at ~/.jitsi-meet-cfg, while making config changes
> rm -rf ~/.jitsi-meet-cfg

## Jibri

Jibri provides services for recording or streaming a Jitsi Meet conference.
A jibri instance can record only one call at a time. The only possible way to use Jibri
in our scenario is to spawn multiple jibri instances. Since jibri takes a lot of resources,
ideally 4 GB RAM as it works by spawning a chrome instance and recording the call using
ffmpeg, the best way to use jibri is spawning an EC2 instance with jibri installed as per our
need. The finalize script on jibri runs after a recording session is complete and uploads
the file to S3. After the upload is complete, the jibri instance is terminated. 

Jibri only needs to be manually deployed once on an EC2 instance, after which an AMI can be prepared
to launch jibri instances on demand. 

To deploy jibri on an EC2 instance, perform the following steps.

Clone this repository
> git clone https://github.com/sarthak-negi/jibri-installation-scripts.git jibri-installation-scripts

cd inside the folder
> cd jibri-installation-scripts

Modify the env.sh accordingly to select the type of instance and subnet. Ensure that
the subnet should be same as the jitsi instance. Also, ensure the security group allows 22
over ssh to successfully ssh into the jibri instance. The JITSI_HOST_IP should be the
private IP of the jitsi meet instance.
The jibri repo url is https://github.com/sarthak-negi/jibri-docker.git
Set this up in the init script.

Start the instance by running
> ./init.sh

Note the id of the instance and ssh into it
Wait for 30 seconds until you see files appear in /home/ubuntu

Ensure that the following files are present:

```
/home/ubuntu/setup_kernel_and_start_jibri.sh

/home/ubuntu/start-jibri-container.sh

/home/ubuntu/finalize_instance.sh

/home/ubuntu/jibri-git

/home/ubuntu/install-linux-kernel.sh
```

Jibri needs snd_aloop module to be loaded. This can be achieved by changing the default
kernel from aws to linux generic. To change the kernel run the underlying command.
Monitor the installation, as a pop up will appear to update the menulist for grub. Choose
`Install the package maintainer's version` which is the first option in the list. The script
will then choose the kernel and reboot.
> ./install-linux-kernel.sh

Ssh into the instance again, and wait till setup_kernel_and_start_jibri.sh has its permissions
changed to non executable. What happens is that this script runs when the system rebooted at the
previous step. It creates a docker image and starts the jibri docker project. After that the
permissions of the files are changed so that it does not recreate the jibri docker image on
reboot as it has already been created. 

For some reason, the bash does not allow setting up of the kernel from the script,
so run the following command to set up snd_aloop

> modprobe snd-aloop

Ensure snd_aloop is present by running
> lsmod | grep snd_aloop

Restart the docker project by navigating to `/home/ubuntu/jibri-git`.

Now run these command to restart the docker project
> docker-compose down
> docker-compose up -d

Run the following command:
> docker ps

If nothing shows up, then run:
> docker ps -a

Get the logs of the jibri container using:
> docker logs -f <jibri_container_name>

Ensure that the finalize script is present in `/home/ubuntu/.jitsi-meet-cfg/jibri/`.
If not, then run these commands
> cp /home/ubuntu/jibri-git/finalize-backup.sh /home/ubuntu/.jitsi-meet-cfg/jibri/finalize.sh

> chmod 775 /home/ubuntu/.jitsi-meet-cfg/jibri/finalize.sh

Restart the docker project and test if everything is working fine.

Once, jibri is up and running, prepare an AMI for the same from the AWS console.

Forked from:
[Jitsi On Docker](https://github.com/jitsi/docker-jitsi-meet)

