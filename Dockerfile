# Usar una imagen base ligera de Node.js
FROM node:20-alpine

# Establecer el directorio de trabajo dentro del contenedor
WORKDIR /app

# Copiar primero los archivos de dependencias para aprovechar el caché de Docker
COPY package*.json ./

# Instalar las dependencias (incluyendo Prisma y Express)
RUN npm install

# Copiar el resto del código del proyecto
COPY . .

# Generar el cliente de Prisma (si aplica en este punto)
RUN npx prisma generate

# Exponer el puerto en el que corre la API (por defecto Express suele usar 3000 o 3001)
EXPOSE 3000

# Comando para iniciar la aplicación en modo desarrollo
CMD ["npm", "run", "dev"]