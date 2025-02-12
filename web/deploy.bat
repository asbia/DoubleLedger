@echo off
REM run build script

REM Pull the latest changes from your version control system
echo Pulling latest changes from Git...
git pull origin main

REM Install dependencies
echo Installing dependencies...
npm install

REM Build the project
echo Building the project...
npm run build

REM Remove any existing Docker containers
echo Removing existing Docker containers...
docker-compose down

REM Build and start Docker containers
echo Building and starting Docker containers...
docker-compose up -d --build

REM Clean up Docker images
echo Cleaning up Docker images...
docker image prune -f

echo Deployment completed successfully!