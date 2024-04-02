# Placeholder to be used once we get the Angular UI up to snuff.

# Dockerfile
FROM node:latest

# Install Angular CLI
RUN npm install -g @angular/cli

# Set the working directory
WORKDIR /app

# Set the entrypoint to a shell
ENTRYPOINT ["/bin/bash"]
