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
* create-room: Generates a random room uuid

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

Cloned from:
[Jitsi On Docker](https://github.com/jitsi/docker-jitsi-meet)

