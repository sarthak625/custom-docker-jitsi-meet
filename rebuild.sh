PASSWORD=$1

docker-compose down
echo $PASSWORD | sudo -S rm -rf ~/.jitsi-meet-cfg
make
docker-compose up -d
