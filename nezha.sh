#!/bin/bash

NZ_BASE_PATH="/opt/nezha"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"

chmod +x $NZ_AGENT_PATH/nezha-agent

./opt/nezha/agent/nezha-agent -s nz_grpc_host:nz_grpc_port -p nz_client_secret
