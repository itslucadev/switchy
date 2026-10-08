#!/usr/bin/env bash

set -exu

gh api repos/itslucadev/switchy/dispatches -f event_type=update-website
