require "log"
require "discordcr"
require "./config.cr"
require "./web.cr"
require "./mysql.cr"
require "./messages.cr"

def main
  Log.setup_from_env

  config = load_config

  client = Discord::Client.new(token: "Bot #{config.discord_token}", client_id: config.discord_client_id.to_u64)
  cache = Discord::Cache.new(client)
  client.cache = cache

  config.web_enabled && spawn Web.main client, config
  config.mysql_enabled && spawn MySQL.main client, config
  config.messages_enabled && spawn Messages.main client, config, cache

  sleep
end

main
