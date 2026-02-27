# Custom OpenClaw image with Matrix plugin dependencies
FROM ghcr.io/openclaw/openclaw:latest

# Switch to root to install dependencies
USER root

# Install Matrix plugin dependencies in the bundled extension
WORKDIR /app/extensions/matrix
RUN npm install --no-save \
    @vector-im/matrix-bot-sdk \
    @matrix-org/matrix-sdk-crypto-nodejs

# Switch back to node user
USER node
WORKDIR /home/node

# Image is ready - entrypoint from base image will be used
