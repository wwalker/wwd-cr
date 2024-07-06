require "http/server"
require "crinja"

class ConfigLine
  getter key : String
  getter label : String
  getter url : String
  getter action : String
  getter image : String
  getter args : String

  def initialize(line)
    values = line.split("|", 5)
    @key = values[0]
    @image = values[1]
    @label = values[2]
    @action = values[3]
    @args = values[4]
    case @action
    when "page"
      @url = "/page/#{@args}"
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

class WDWD
  def initialize(@rows, @columns, @config_file)
    @config_lines = read_config(@config_file)
    @os = self.set_os
  end # initialize

def render_page(page, title)
  w = ((100 - 1*(@rows + 1))/@rows).to_i
  h = ((100 - 1*(@columns + 1))/@columns).to_i
  tr_height = "150px"
  image_width = "135px"
  image_height = "135px"

  renderer = Renderer.new

  row_text = ""
  (1..@rows).each do |row|
    row_content = ""
    (1..@columns).each do |column|
      key = "#{page}-#{row}-#{column}"
      c = config_lines[key]
      context = {key: key, label: c.label, action: c.action, w: w, h: h, image: c.image, image_width: image_width, image_height: image_height, url: c.url}
      row_content += renderer.render("td_html.j2", context)
    end
    row_text += renderer.render("tr_html.j2", {row_content: row_content, tr_height: tr_height})
  end

  renderer.render("deck_html.j2", {page: page, title: title, table_content: row_text, table_width: "1200px"})
end

  def run_server(port : Int32)
    config_lines = read_config(@config_file)

    server = HTTP::Server.new do |context|
      case context.request.method
      when "GET"
        context.response.status = HTTP::Status::OK
        case context.request.path
        when "", "/"
          context.response.print INDEX_HTML
        when "/start.html"
          context.response.print START_HTML
        when /^\/re-read-config$/
          config_lines = read_config(config_file)
          context.response.print "Config re-read\n\n"
        when /^\/page\/(\d+)$/
          page = $1.to_i
          STDERR.puts "rendering page #{$1}\n\n"
          context.response.print render_page(page, "Page: #{page}")
        when /^\/images\/(.*)$/
          context.response.print File.read("images/#{$1}")
        when /^\/pressed\/(\d+-\d+-\d+)$/
          key = $1
          key =~ /^(\d+)-/
          page_num = $1.to_i
          cl = config_lines[key]
          STDERR.puts "I should execute something for #{key}\n\n"
          STDERR.puts "action: #{cl.action}\n\n"
          STDERR.puts "args: <#{cl.args}>\n\n"

          case cl.action
          when "shortcut"
            # Process.new(cl.args,nil,nil,false,true)
            # File.write("shortcut.bat", "cmd /c " + cl.args)
            # Process.new("shortcut.bato")
            Process.new("cmd", ["/c", cl.args])
            context.response.status = HTTP::Status::FOUND
            context.response.headers["Location"] = "/page/#{page_num}"
          when "keys"
            File.write("oneshot.ahk", "Send " + cl.args)
            Process.new("C:/Program Files/AutoHotkey/v2/AutoHotkey64.exe", ["oneshot.ahk"])
            # Process.new("C:/Program Files/AutoHotkey/v1.1.37.02/AutoHotkeyU64.exe", ["oneshot.ahk"])
            context.response.status = HTTP::Status::FOUND
            context.response.headers["Location"] = "/page/#{page_num}"
          when "cmd"
            args = cl.args.split("|")
            command = args.shift
            Process.new(command, args)
            context.response.status = HTTP::Status::FOUND
            context.response.headers["Location"] = "/page/#{page_num}"
          else
            context.response.status = HTTP::Status::BAD_REQUEST
            context.response.print "Unknown command type #{cl.action}!\n\n"
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

    address = server.bind_tcp "0.0.0.0", 5657, true
    puts "Listening on http://#{address}"

    # This call blocks until the process is terminated
    server.listen
  end # run_server

  def run
    run_server(8080)
  end
end # class WDWD

def main
  rows = ARGV[0].to_i
  columns = ARGV[1].to_i
  file = ARGV[2]

  wdwd = WDWD.new(rows, columns, file)
  wdwd.run
end

INDEX_HTML = {{ read_file("#{__DIR__}/../files/index.html") }}
START_HTML = {{ read_file("#{__DIR__}/../files/start.html") }}
STDERR.puts "Running on Crystal #{Crystal::VERSION} #{Crystal::HOST_TRIPLE}\n\n"

case Crystal::HOST_TRIPLE
when /windows/
  STDERR.puts "Running on Windows\n\n"
  @os = "windows"
when /linux/
  STDERR.puts "Running on Linux\n\n"
  @os = "linux"
when /darwin/
  STDERR.puts "Running on macOS\n\n"
  @os = "macos"
else
  STDERR.puts "Unknown host triple #{Crystal::HOST_TRIPLE}"
  exit 2 # Unknown OS
end

main()
