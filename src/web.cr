require "http/server"
require "discordcr"
require "crypto/subtle"

module Web
  extend self

  struct AuthorOrRepo
    include JSON::Serializable

    property name : String

    def initialize(@name)
    end
  end

  struct Commit
    include JSON::Serializable

    property id : String
    property message : String
    property author : AuthorOrRepo

    def initialize(@id, @message, @author)
    end
  end

  struct Github
    include JSON::Serializable

    property ref : String
    property repository : AuthorOrRepo
    property commits : Array(Commit)

    def initialize(@ref, @repository, @commits)
    end
  end

  REGEX = /(?:\r\n|\r|\n)/

  CID_GITHUB = Discord::Snowflake.new(478623542380855306_u64)

  def main(client, config)
    server = HTTP::Server.new do |context|
      req = context.request
      resp = context.response

      if req.method != "POST"
        resp.respond_with_status(HTTP::Status::METHOD_NOT_ALLOWED)
        next
      end

      query = req.query_params

      token = query.fetch("token", "")

      if !Crypto::Subtle.constant_time_compare(config.botapi_token, token)
        resp.respond_with_status(HTTP::Status::FORBIDDEN, "Invalid token")
        next
      end

      if req.body.nil?
        resp.respond_with_status(HTTP::Status::BAD_REQUEST, "Body is empty")
        next
      end

      body = req.body.not_nil!.gets_to_end

      if query.has_key?("github")
        puts "Handling github web hook"

        begin
          github = Github.from_json(body)

          ref = github.ref.split('/').last
          commits = github.commits

          text = ""

          commits.each do |commit|
            text += "$Commit \##{commit.id[0..7]} by #{commit.author.name}\n #{commit.message.gsub(REGEX, "\n ")}"
          end

          client.create_message(CID_GITHUB, "```md\n#{commits.size} new commit(s) of #{github.repository.name}:#{ref}\n #{text} ```")

          resp.respond_with_status(HTTP::Status::OK, "")
          next
        rescue
          resp.respond_with_status(HTTP::Status::BAD_REQUEST, "Can't parse Github body")
          next
        end
      end

      begin
        message = URI::Params.parse(body)
        channelID = Discord::Snowflake.new(message.fetch("channelID", "544557150064738315"))
        content = message["content"]
        if content.size < 1 || content.size > 2000
          raise "Content size is invalid"
        end
        puts "Passing message #{content} to #{channelID}"
        client.create_message(channelID, content)
      rescue
        resp.respond_with_status(HTTP::Status::BAD_REQUEST, "Can't parse Message body")
        next
      end
    end

    address = ""
    if config.web_ssl
      context = OpenSSL::SSL::Context::Server.new
      context.certificate_chain = config.web_cert
      context.private_key = config.web_privkey
      address = server.bind_tls config.web_hostname, config.web_port, context
    else
      address = server.bind_tcp config.web_hostname, config.web_port
    end
    puts "Listening on http://#{address}"
    server.listen
  end
end
