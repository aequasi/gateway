# Shards

The shards app is the app that actually runs the shards. GENIUS!!! *insert stephen hawkins meme*


## ENV variables

 - `TOKEN` the Discord bot token
 - `SHARDS_COUNT` shards number (default: 1)
 - `BUCKET_ID` shards bucket id (default: 0)
 - `BUCKETS_COUNT` buckets number (default: 1)
 - `CITADEL_DOMAIN` the name of your cluster
 - `CITADEL_REDIS_URL` the redis url for your cluster discovery

Basically buckets are a meann to define which shards we start-up.

For example if we have `SHARDS_COUNT=20` and `BUCKETS_COUNT=5` then:

- `BUCKET_ID=0` will start shard 0, 1, 2 and 3.
- `BUCKET_ID=1` will start shard 4, 5, 6 and 7.
- `BUCKET_ID=2` will start shard 8, 9, 10, 11.
- `BUCKET_ID=3` will start shard 12, 13, 14 and 15.
- `BUCKET_ID=4` will start shard 16, 17, 18, 19.

