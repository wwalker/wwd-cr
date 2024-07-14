all: bin/wwd-server

bin/wwd-server: src/wwd.cr shard.yml shard.lock
	shards build --error-trace wwd-server
