# Stage 1: Build React App
FROM node:18-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci

COPY . .
# Set API target host for frappe-react-sdk build if needed
ENV REACT_APP_FRAPPE_URL=http://localhost:${HOMABAY_BACKEND_PORT}
# RUN npm run build

# Stage 2: Serve using Nginx
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
# Custom SPA route handling
RUN echo 'server { listen 80; location / { root /usr/share/nginx/html; index index.html; try_files $uri /index.html; } }' > /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]