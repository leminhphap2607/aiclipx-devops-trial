
FROM node:16.20.1
WORKDIR /app
COPY package.json ./
RUN npm install \
    npm install --save-dev jest
COPY . .
EXPOSE 5000
CMD ["npm","run","start"]