require "discordcr"
require "http/client"
require "bson"
require "sqlite3"

module Messages
  extend self

  struct Attachment
    include BSON::Serializable
    property filename : String
    property bytes : Bytes

    def initialize(@filename, @bytes)
    end
  end

  struct CachedMessage
    include BSON::Serializable
    property id : Int64
    property channel_id : Int64
    property author : Int64
    property timestamp : Time
    property content : String
    property attachments : Array(Attachment)

    def initialize(id : Discord::Snowflake, channel_id : Discord::Snowflake, author : Discord::Snowflake, @timestamp, @content, @attachments)
      @id = id.to_u64.to_i64!
      @channel_id = channel_id.to_u64.to_i64!
      @author = author.to_u64.to_i64!
    end

    def id!
      Discord::Snowflake.new(@id.to_u64!)
    end

    def channel_id!
      Discord::Snowflake.new(@channel_id.to_u64!)
    end

    def author!
      Discord::Snowflake.new(@author.to_u64!)
    end
  end

  ChannelID_Log = Discord::Snowflake.new(697846732201000970_u64)
  MaxFileSize   = (2**20)*16

  def db_table(db, channelid)
    db.exec "CREATE TABLE IF NOT EXISTS `#{channelid.value.to_s}` (id INTEGER PRIMARY KEY, timestamp INTEGER,message BLOB);"
  end

  def get_avatar_url(user_id, avatar)
    if avatar.nil?
      return "https://cdn.discordapp.com/embed/avatars/1.png"
    end

    return "https://cdn.discordapp.com/avatars/#{user_id}/a_#{avatar}.webp?size=256"
  end

  def main(client, cache)
    client.on_ready do |payload|
      puts "User '#{payload.user.username}' is ready"
      client.status_update(game: Discord::GamePlaying.new("Bonjour monsieur", Discord::GamePlaying::Type::Playing))
    end

    db = DB.open "sqlite3://./messages.db"

    spawn do
      loop do
        tables = Array(String).new
        db.query "SELECT name FROM sqlite_master WHERE type='table'" do |rs|
          rs.each do
            tables.push(rs.read(String))
          end
        end
        tables.each do |table|
          db.exec "DELETE FROM `#{table}` WHERE timestamp <= date('now','-7 day')"
        end
        sleep 3.hours
      end
    end

    client.on_message_create do |payload|
      if payload.channel_id == ChannelID_Log
        next
      end

      db_table(db, payload.channel_id)

      images = Array(Attachment).new(16)

      puts "Caching #{payload.attachments.size} attachment(s)"
      payload.attachments.each do |attach|
        if attach.size < MaxFileSize
          HTTP::Client.get(attach.url) do |response|
            if response.success?
              body = Bytes.new(attach.size)
              body_io = response.body_io
              body_io.read_fully(body)
              if !body.nil?
                images.push(Attachment.new(attach.filename, body))
              end
            end
          end
        else
          puts "File is too huge #{attach}"
        end
      end

      msg = CachedMessage.new(payload.id, payload.channel_id, payload.author.id, payload.timestamp, payload.content, images)
      args = [] of DB::Any
      args << msg.id
      args << msg.to_bson.data
      db.exec "insert into `#{msg.channel_id.to_s}` values (?, date('now') , ?)", args: args
      puts "Cached message #{payload.id} in channel #{payload.channel_id}"
    end

    client.on_message_update do |payload|
      if payload.channel_id == ChannelID_Log
        next
      end

      db_table(db, payload.channel_id)

      args = [] of DB::Any
      args << payload.id.value.to_i64!
      oldmsg : CachedMessage? = nil
      db.query "select message from `#{payload.channel_id.value.to_s}` WHERE id = ?", args: args do |rs|
        rs.each do
          oldmsg = CachedMessage.from_bson(BSON.new(rs.read(Bytes)))
        end
      end

      if oldmsg.nil? || payload.content.nil?
        next
      end

      channel = cache.resolve_channel(payload.channel_id)
      author = cache.resolve_user(oldmsg.author!)
      embed = Discord::Embed.new(
        colour: 0xffd700_u32,
        title: "at #{channel.name}",
        author: Discord::EmbedAuthor.new(author.username, icon_url: get_avatar_url(author.id, author.avatar)),
        description: "#{oldmsg.content} -> #{payload.content}",
        timestamp: oldmsg.timestamp,
        footer: Discord::EmbedFooter.new("A:#{author.id} | M:#{payload.id}")
      )
      puts "Logging changed message #{payload.id}"
      client.create_message(ChannelID_Log, "", embed)
    end

    client.on_message_delete do |payload|
      if payload.channel_id == ChannelID_Log
        next
      end

      db_table(db, payload.channel_id)

      args = [] of DB::Any
      args << payload.id.value.to_i64!
      oldmsg : CachedMessage? = nil
      db.query "select message from `#{payload.channel_id.value.to_s}` WHERE id = ?", args: args do |rs|
        rs.each do
          oldmsg = CachedMessage.from_bson(BSON.new(rs.read(Bytes)))
        end
      end

      if oldmsg.nil?
        next
      end

      channel = cache.resolve_channel(payload.channel_id)
      author = cache.resolve_user(oldmsg.author!)

      embed = Discord::Embed.new(
        colour: 0xb90702_u32,
        title: "at #{channel.name}",
        author: Discord::EmbedAuthor.new("#{author.username}\##{author.discriminator}", icon_url: get_avatar_url(author.id, author.avatar)),
        description: oldmsg.content,
        timestamp: oldmsg.timestamp,
        footer: Discord::EmbedFooter.new("A:#{author.id} | M:#{payload.id}")
      )

      puts "Logging deleted message #{payload.id}"

      client.create_message(ChannelID_Log, "", embed)

      puts "Restoring #{oldmsg.attachments.size} attachment(s)"

      oldmsg.attachments.each do |attach|
        sleep 1.seconds
        io = IO::Memory.new(attach.bytes)
        client.upload_file(ChannelID_Log, "", io, attach.filename, nil, true)
      end

      db.exec "delete from `#{payload.channel_id.value.to_s}` WHERE id = ?", args: args
    end

    voice_state = Hash(Discord::Snowflake, Discord::Snowflake?).new

    client.on_voice_state_update do |payload|
      color = 0x1a7701_u32
      message = "joined"
      oldvc_channel = voice_state[payload.user_id]?
      vc_channel = payload.channel_id

      if !oldvc_channel.nil? && payload.channel_id.nil?
        vc_channel = oldvc_channel
        color = 0x77011a_u32
        message = "left"
      end

      if vc_channel.nil? || oldvc_channel == payload.channel_id
        next
      end

      voice_state[payload.user_id] = payload.channel_id

      channel = cache.resolve_channel(vc_channel.not_nil!)
      user = cache.resolve_user(payload.user_id)
      embed = Discord::Embed.new(
        colour: color,
        author: Discord::EmbedAuthor.new(user.username, icon_url: get_avatar_url(user.id, user.avatar)),
        description: "#{user.username}\##{user.discriminator} #{message} the voice chat 🔈#{channel.name}",
        footer: Discord::EmbedFooter.new("A:#{user.id} | VC:#{channel.id}")
      )

      puts "Logging voice state #{message} #{user.username}\##{user.discriminator}"

      client.create_message(ChannelID_Log, "", embed)
    end
    client.run
  end
end
