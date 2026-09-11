FROM node:20-bullseye-slim AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npx prisma generate
RUN npm run build

FROM node:20-bullseye-slim AS runner

ENV NODE_ENV=production

RUN groupadd --system app && useradd --system --gid app --home-dir /home/app --create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force

COPY --from=builder --chown=app:app /app/dist ./dist
COPY --from=builder --chown=app:app /app/prisma ./prisma
COPY --from=builder --chown=app:app /app/node_modules/.prisma ./node_modules/.prisma

USER app

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["node", "-e", "const port = Number(process.env.PORT) || 3000; fetch('http://127.0.0.1:' + port + '/v1/health').then((response) => { if (!response.ok) process.exit(1); }).catch(() => process.exit(1));"]

CMD ["node", "dist/main.js"]
