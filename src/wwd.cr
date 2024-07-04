require "http/server"
require "crinja"

# class RenderPage
#   @page : Int32
#   @title : String
#   @rows : Int32
#   @columns : Int32
#   @config_lines : Array(ConfigLine)
#   @width : Int32
#   @height : Int32
#
#   property html : String
#
#   def initialize(@page, @title, @rows, @columns, file, @width, @height)
#
#     env = Crinja.new
#     env.loader = Crinja::Loader::FileSystemLoader.new("templates/")
#     template = env.get_template("deck.html.j2")
#     @html = template.render({page: @page, title: @title, rows: @rows, columns: @columns, w: @width, h: @height, config_lines: @config_lines})
#   end
# end

class ConfigLine
  getter key : String
  getter label : String
  getter command : String
  getter url : String
  getter? image : Bool

  def initialize(line)
    values = line.split(" : ")
    @key = values[0]
    @label = values[1]
    @command = values[2]
    # @image = (values[3] =~ /.*\.(jpg|jpeg|png|gif|svg|webp|tif|tiff)$/) ? true : false
    @image = (values[3] =~ /^(yes|y|true|t)$/i) ? true : false
    case @command
    when /^\s*page\s+(\d+)$/
      @url = "/page/#{$1}"
    else
      @url = "/pressed/#{@key}"
    end
  end
end

class Renderer
  def initialize
    @env = Crinja.new
    @env.loader = Crinja::Loader::FileSystemLoader.new("templates/")
  end

  def render(template, context)
    template = @env.get_template(template)
    template.render(context)
  end
end

def read_config(file)
  config_lines = {} of String => ConfigLine
  File.read_lines(file).each { |line| cl = ConfigLine.new(line); config_lines[cl.key] = cl }
  config_lines
end

def render_page(page, title, rows, columns, config_lines)
  w = ((100 - 1*(rows + 1))/rows).to_i
  h = ((100 - 1*(columns + 1))/columns).to_i
  tr_height = "150px"
  image_width = "135px"
  image_height = "135px"

  renderer = Renderer.new

  row_text = ""
  (1..rows).each do |row|
    row_content = ""
    (1..columns).each do |column|
      key = "#{page}-#{row}-#{column}"
      c = config_lines[key]
      context = {key: key, label: c.label, command: c.command, w: w, h: h, image: c.image?, image_width: image_width, image_height: image_height, url: c.url}
      row_content += renderer.render("td_html.j2", context)
    end
    row_text += renderer.render("tr_html.j2", {row_content: row_content, tr_height: tr_height})
  end

  renderer.render("deck_html.j2", {page: page, title: title, table_content: row_text, table_width: "1200px"})
end

def run_server(port : Int32, config_file : String, rows : Int32, columns : Int32)
  config_lines = read_config(config_file)

  server = HTTP::Server.new do |context|
    case context.request.method
    when "GET"
      context.response.status = HTTP::Status::OK
      case context.request.path
      when /^\/re-read-config$/
        config_lines = read_config(config_file)
        context.response.print "Config re-read\n\n"
      when /^\/page\/(\d+)$/
        page = $1.to_i
        STDERR.puts "rendering page #{$1}\n\n"
        context.response.print render_page(page, "Page: #{page}", rows, columns, read_config(config_file))
      when /^\/images\/(.*)$/
        context.response.print File.read("images/#{$1}")
      when /^\/pressed\/(\d+-\d+-\d+)$/
        key = $1
        key =~ /^(\d+)-/
        page_num = $1.to_i
        STDERR.puts "I should execute something for #{key}\n\n"
        cmd = config_lines[key].command
        cmd =~ /^(.+?)\s+(.*)/
        type = $1
        data = $2
        STDERR.puts "type: #{type}\n\n"
        STDERR.puts "data: #{data}\n\n"

        case type
        when "keys"
          Process.new("xdotool", ["key", data])
          context.response.status = HTTP::Status::FOUND
          context.response.headers["Location"] = "/page/#{page_num}"
        when "cmd"
          args = data.split(/\s+/)
          STDERR.puts "args: <#{args.join("|")}>\n\n"
          command = args.shift
          Process.new(command, args)
          context.response.status = HTTP::Status::FOUND
          context.response.headers["Location"] = "/page/#{page_num}"
        else
          context.response.status = HTTP::Status::BAD_REQUEST
          context.response.print "Unknown command type #{type}!\n\n"
        end
      else
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.print "Request path is invalid #{context.request.path}!\n\n"
      end
    else
      context.response.status = HTTP::Status::METHOD_NOT_ALLOWED
      context.response.headers["Allow"] = "GET, POST"
      context.response.print "Method Not Allowed\n"
    end
  end

  address = server.bind_tcp(8080)
  puts "Listening on http://#{address}"

  # This call blocks until the process is terminated
  server.listen
end

def main
  rows = ARGV[0].to_i
  columns = ARGV[1].to_i
  file = ARGV[2]

  run_server(8080, file, rows, columns)
end

main()
