require "http/server"
require "crinja"
require "qr-code"

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
    end # case
  end   # initialize
end     # class ConfigLine

class Renderer
  def initialize
    @env = Crinja.new
    @env.loader = Crinja::Loader::FileSystemLoader.new("templates/")
  end # initialize

  def render(template, context)
    template = @env.get_template(template)
    template.render(context)
  end # render
end

class WDWD
  @rows : Int32
  @columns : Int32
  @config_file : String
  @config_lines : Hash(String, ConfigLine)
  @port : Int32
  getter os : String

  def initialize(@rows, @columns, @config_file, @port = 5657)
    @config_lines = read_config(@config_file)
    @os = os
  end # initialize

  def os
    case Crystal::HOST_TRIPLE
    when /windows/
      STDERR.puts "Running on Windows\n\n"
      "windows"
    when /linux/
      STDERR.puts "Running on Linux\n\n"
      "linux"
    when /darwin/
      STDERR.puts "Running on macOS\n\n"
      "macos"
    else
      STDERR.puts "Unknown host triple #{Crystal::HOST_TRIPLE}"
      exit 2 # Unknown OS
    end
  end # os

  def read_config(file)
    config_lines = Hash(String, ConfigLine).new
    lines = File.read_lines(file)
    # STDERR.puts "Reading config from #{file}\n\n"
    # STDERR.puts "Lines: #{lines}\n\n"
    noncomments = lines.reject { |l| l =~ /^#/ }
    # STDERR.puts "Noncomments: #{noncomments}\n\n"
    noncomments.each { |line| cl = ConfigLine.new(line); config_lines[cl.key] = cl }
    # config_lines.nil? ? raise "No config lines found in #{file}" : config_lines
    config_lines
  end # read_config

  def button_config(page, row, column) : ConfigLine
    key = "#{page}-#{row}-#{column}"
    default_key = "0-#{row}-#{column}"

    bc = @config_lines[key]?
    if !bc.nil?
      return bc
    else
      bc = @config_lines[default_key]?
    end
    if !bc.nil?
      return bc
    else
      # TODO actually use the "0-0-0" config, if it  exists
      bc = ConfigLine.new("#{key}||#{key}|undefined|undefined")
    end
    bc.nil? ? raise "No default button config found for #{key}" : bc
  end

  def render_page(page, title)
    # TODO replace with "magic javascript" to auto size everything
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
        bc = button_config(page, row, column)
        context = {key: key, w: w, h: h,
                   image_width: image_width, image_height: image_height,
                   label: bc.label, action: bc.action, image: bc.image, url: bc.url}
        row_content += renderer.render("td_html.j2", context)
      end
      row_text += renderer.render("tr_html.j2", {row_content: row_content, tr_height: tr_height})
    end

    renderer.render("deck_html.j2", {page: page, title: title, table_content: row_text, table_width: "1200px"})
  end # render_page

  def handle_button_press(page, row, column, context)
    key = "#{page}-#{row}-#{column}"
    cl = button_config(page, row, column)
    STDERR.puts "I should execute something for #{key}\n\n"
    STDERR.puts "action: #{cl.action}\n\n"
    STDERR.puts "args: <#{cl.args}>\n\n"

    case cl.action
    when "die-die-die"
      STDERR.puts "Exiting, as requested by /die-die-die\n\n"
    when "re-read-config"
      @config_lines = read_config(@config_file)
      context.response.status = HTTP::Status::FOUND
      context.response.headers["Location"] = "/page/#{page}"
    when "undefined"
      # TODO generate a popup pointing out the key is undefined
      context.response.status = HTTP::Status::FOUND
      context.response.headers["Location"] = "/page/#{page}"
    when "shortcut"
      Process.new("cmd", ["/c", cl.args])
      context.response.status = HTTP::Status::FOUND
      context.response.headers["Location"] = "/page/#{page}"
    when "keys"
      File.write("oneshot.ahk", "Send " + cl.args)
      Process.new("C:/Program Files/AutoHotkey/v2/AutoHotkey64.exe", ["oneshot.ahk"])
      # Process.new("C:/Program Files/AutoHotkey/v1.1.37.02/AutoHotkeyU64.exe", ["oneshot.ahk"])
      context.response.status = HTTP::Status::FOUND
      context.response.headers["Location"] = "/page/#{page}"
    when "cmd"
      args = cl.args.split("|")
      command = args.shift
      Process.new(command, args)
      context.response.status = HTTP::Status::FOUND
      context.response.headers["Location"] = "/page/#{page}"
    else
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.print "Unknown command type #{cl.action}!\n\n"
    end # case
  end   # handle_button_press

  def run_server(port : Int32)
    @config_lines = read_config(@config_file)

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
          @config_lines = read_config(@config_file)
          context.response.print "Config re-read\n\n"
        when /^\/page\/(\d+)$/
          page = $1.to_i
          STDERR.puts "rendering page #{$1}\n\n"
          context.response.print render_page(page, "Page: #{page}")
        when /^\/qr\/(.*)$/
          STDERR.puts "QR code for <#{$1}>\n\n"
          context.response.print qr_page($1)
          context.response.status = HTTP::Status::OK
        when /^\/images\/(.*)$/
          context.response.print File.read("images/#{$1}")
        when /^\/pressed\/(\d+)-(\d+)-(\d+)$/
          handle_button_press($1, $2, $3, context)
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

  def ips
    case @os
    when "windows"
      `ipconfig`.scan(/IPv4 Address.*: (\d+\.\d+\.\d+\.\d+)/).reject { |m| (m =~ /(\d+\.\d+\.\d+\.\d+)/).nil?}.map { |m| m[0] }
    when "linux"
      `hostname -I`.split(" ").reject{ |ip| (ip =~ /\d+\.\d+\.\d+\.\d+/).nil? }
    when "macos"
      `ipconfig getifaddr en0`.split("\n").reject{ |ip| (ip =~ /\d+\.\d+\.\d+\.\d+/).nil? }
    else
      raise "Unknown OS #{@os}"
    end
  end

  def qr_page(ip)
    ip =~ /(\d+\.\d+\.\d+\.\d+)/ || raise "Invalid IP address #{ip}"
    ip = $1
    title = "QR Code for #{ip} / #{@port}"
    image_name = "images/qr-#{ip}:#{@port}.svg"
    image_url = "http://localhost:#{@port}/#{image_name}"
    qr_code_text = "http://#{ip}:#{@port}/"

    File.write("#{image_name}", QRCode.new(qr_code_text).as_svg)

    renderer = Renderer.new
    renderer.render("qr_code_html.j2", {title: title, image_url: image_url, target_url: qr_code_text, ip: ip, port: @port})
  end

  def print_qr_urls
    p ips
    ips.each do |ip|
      STDERR.puts "http://#{ip}:#{@port}/qr/#{ip}:#{@port}"
    end
  end

  def run
    run_server(@port)
  end
end # class WDWD

def main
  rows = ARGV[0].to_i
  columns = ARGV[1].to_i
  file = ARGV[2]
  # TODO handle optional port numbers
  port = 5657

  wdwd = WDWD.new(rows, columns, file, port)
  wdwd.print_qr_urls
  wdwd.run
end

INDEX_HTML = {{ read_file("#{__DIR__}/../files/index.html") }}
START_HTML = {{ read_file("#{__DIR__}/../files/start.html") }}
STDERR.puts "Running on Crystal #{Crystal::VERSION} #{Crystal::HOST_TRIPLE}\n\n"

main()
