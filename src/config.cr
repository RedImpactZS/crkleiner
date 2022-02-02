require "log"
require "yaml"

struct Config
  include YAML::Serializable

  property messages_enabled : Bool = true
  property messages_welcome : String = "Bot is ready"
  property web_enabled : Bool = true
  property web_hostname : String = "localhost"
  property web_port : Int32 = 3444
  property botapi_token : String
  property discord_token : String
  property discord_client_id : String
  property mysql_enabled : Bool = true
  property mysql_hostname : String = "localhost"
  property mysql_port : Int32 = 3306
  property mysql_user : String = "root"
  property mysql_password : String
  property mysql_dbname : String
  property web_ssl : Bool = true
  property web_privkey : String = ""
  property web_cert : String = ""
  
end

def load_config
  file = ARGV[0]? || "config.yml"
  Log.info { "Loading config from #{file}" }
  return Config.from_yaml(File.read(file))
end
