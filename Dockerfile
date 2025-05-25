# Use official Node.js runtime as base image
FROM node:20-alpine

# Build arguments for dynamic labels
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION=1.0.0
ARG BUILD_NUMBER

# Add labels for image metadata and description
LABEL maintainer="your-email@example.com"
LABEL description="Node.js application with CI/CD pipeline for GCP deployment"
LABEL version="${VERSION}"
LABEL org.opencontainers.image.title="My Node.js App"
LABEL org.opencontainers.image.description="A production-ready Node.js application with Docker containerization and GCP deployment"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.vendor="Your Company Name"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.source="https://github.com/your-username/your-repo"
LABEL org.opencontainers.image.documentation="https://github.com/your-username/your-repo/blob/main/README.md"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${VCS_REF}"
LABEL build.number="${BUILD_NUMBER}"

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