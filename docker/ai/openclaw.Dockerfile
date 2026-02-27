# Custom OpenClaw image with Matrix plugin dependencies
FROM ghcr.io/openclaw/openclaw:latest

# Install Matrix dependencies as root without changing working directory
USER root
RUN cd /app/extensions/matrix && \
    npm install --no-save @vector-im/matrix-bot-sdk @matrix-org/matrix-sdk-crypto-nodejs && \
    chown -R node:node node_modules
USER node

# Image is ready - entrypoint and workdir from base image will be used
