#!/bin/bash
set -e

psql -U postgres -c "CREATE ROLE repmgr LOGIN SUPERUSER PASSWORD '${REPMGR_PASSWORD}';"
psql -U postgres -c "CREATE DATABASE repmgr OWNER repmgr;"
