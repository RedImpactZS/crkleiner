require "mysql"
require "discordcr"

module MySQL
  extend self

  struct ServerData
    property id, players, slots, map

    def initialize(@id : Int32, @players : Int32, @slots : Int32, @map : String)
    end
  end

  IDNAMES = ["UNK", "ZS", "PS"]

  def main(client, config)
    puts "MySQL task is ready"
    DB.open "mysql://#{config.mysql_user}:#{config.mysql_password}@#{config.mysql_hostname}:#{config.mysql_port}/#{config.mysql_dbname}" do |db|
      lastid = 0
      loop do
        sdata = Array(ServerData).new

        db.query "SELECT id,players,slots,map FROM `gex_servers` WHERE id < 100 ORDER BY id" do |rs|
          rs.each do
            sdata.push(ServerData.new(rs.read(Int32), rs.read(Int32), rs.read(Int32), rs.read(String)))
          end
        end

        data = sdata[lastid]
        sname = IDNAMES[data.id]? || IDNAMES[0]
        map = data.map[0..11]

        game = "#{sname}|#{map}|#{data.players}/#{data.slots}"

        spawn client.status_update(game: Discord::GamePlaying.new(game, Discord::GamePlaying::Type::Playing))

        lastid += 1
        if lastid == sdata.size
          lastid = 0
        end

        sleep 15.seconds
      end
    end
  end
end
