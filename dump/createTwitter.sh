#!/bin/bash

#start server
mkdir -p /data/sh/config
mongod --port 8000 --configsvr --dbpath /data/sh/config &

#start router
mongos --port 10000 --configdb localhost:8000 --chunkSize 16 &

#create shards
mkdir -p /data/sh/shard1
mkdir -p /data/sh/shard2
mongod --port 10001 -dbpath /data/sh/shard1 &
mongod --port 10002 -dbpath /data/sh/shard2 &

sleep 5

#import tweets
mongorestore --port 10001 -d twitter /dump/tweets.bson
mongo --port 10001 twitter --eval 'db.tweets.remove({"user.screen_name":null})'
mongo --port 10000 --eval 'sh.addShard("localhost:10001")'
mongo --port 10000 --eval 'sh.addShard("localhost:10002")'
mongo --port 10000 --eval 'sh.enableSharding("twitter")'
mongo twitter --port 10000 --eval 'db.tweets.ensureIndex({"user.screen_name": 1})'
mongo twitter --port 10000 --eval 'sh.shardCollection("twitter.tweets",{"user.screen_name": 1})'

# Naive check runs checks once 10 seconds to see if either of the processes exited.
# This illustrates part of the heavy lifting you need to do if you want to run
# more than one service in a container. The container exits with an error
# if it detects that either of the processes has exited.
# Otherwise it loops forever, waking up every 60 seconds

echo ------------------------------------------ Start finished ------------------------------------------

while sleep 10; do
  ps aux |grep "mongod --port 8000 --configsvr --dbpath /data/sh/config" |grep -q -v grep
  PROCESS_1_STATUS=$?
  ps aux |grep "mongos --port 10000 --configdb localhost:8000 --chunkSize 16" |grep -q -v grep
  PROCESS_2_STATUS=$?
  ps aux |grep "mongod --port 10001 -dbpath /data/sh/shard1" |grep -q -v grep
  PROCESS_3_STATUS=$?
  ps aux |grep "mongod --port 10002 -dbpath /data/sh/shard2" |grep -q -v grep
  PROCESS_4_STATUS=$?
  # If the greps above find anything, they exit with 0 status
  # If they are not both 0, then something is wrong
  if [ $PROCESS_1_STATUS -ne 0 -o $PROCESS_2_STATUS -ne 0 -o $PROCESS_3_STATUS -ne 0 -o $PROCESS_4_STATUS -ne 0 ]; then
    echo "------------------------------------------ One of the processes has already exited. ------------------------------------------"
    exit 1
  fi
done