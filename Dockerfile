# Use the official Node.js image as the base image
FROM node:16

# Set the working directory inside the container
WORKDIR /app

# Copy package.json and package-lock.json to the working directory
COPY package*.json ./

# Install the dependencies
RUN npm install

# Copy the rest of the application code to the working directory
COPY . .

# Copy the start script to the working directory
COPY start.sh .

# Make the start script executable
RUN chmod +x start.sh

# Set environment variables
ENV HUB_IP=${HUB_IP} \
    HUB_API_KEY=${HUB_API_KEY}

# Expose the port the app runs on
EXPOSE 8080

# Command to run the application
CMD ["./start.sh"]