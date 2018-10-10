#!/bin/bash
set -o errexit
exec rspamc -h /run/rspamd.sock learn_ham
