# Use official Node.js runtime as base image
FROM node:20-alpine

# Set working directory in container
WORKDIR /app

# Copy package files first (for better Docker layer caching)
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY . .

# Mount secret and use it during build (if needed)
# This demonstrates how to use Docker secrets during build
RUN --mount=type=secret,id=env \
    if [ -f /run/secrets/env ]; then \
        echo "Environment file found during build"; \
        cat /run/secrets/env; \
    fi

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001

# Change ownership of app directory
RUN chown -R nextjs:nodejs /app
USER nextjs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) })"

# Start the application
CMD ["npm", "start"]