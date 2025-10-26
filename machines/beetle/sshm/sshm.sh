#!/bin/bash 

# author: meanii (https://github.com/meanii)
# This script is run on the remote server to set up the reverse tunnel
# It is run as root

ssh -nNTv -R 0.0.0.0:2222:localhost:22 root@meanii.dev