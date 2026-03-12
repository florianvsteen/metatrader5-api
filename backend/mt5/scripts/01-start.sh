#!/bin/bash
source /scripts/02-common.sh

# Redirect all output to stdout so Portainer captures everything
exec 1> >(tee -a /var/log/mt5_setup.log) 2>&1

/scripts/03-install-mono.sh
/scripts/04-install-mt5.sh
/scripts/05-install-python.sh
/scripts/06-install-libraries.sh
/scripts/07-start-wine-flask.sh

tail -f /dev/null
