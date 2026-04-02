FROM node:18-alpine
RUN apk update && apk add --no-cache nmap && \
    echo @edge http://nl.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories && \
    echo @edge http://nl.alpinelinux.org/alpine/edge/main >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache \
      chromium \
      harfbuzz \
      "freetype>2.8" \
      ttf-freefont \
      nss

RUN fc-cache -f && rm -rf /var/cache/*

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
ENV PATH /app/node_modules/.bin:$PATH
COPY package.json ./
RUN npm ci
COPY . ./
RUN chown -R appuser:appgroup /app
USER appuser
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD wget -qO- http://localhost:${PORT:-8078}/health || exit 1
CMD ["npm", "start"]
