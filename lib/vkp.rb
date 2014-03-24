require 'vkp/version.rb'
require 'yaml'
require 'net/http'
require 'net/https'
require 'openssl'	
require 'nokogiri'
require 'httpclient'
require 'json'
require 'timers'

class VkontaktePlayer
  
  def initialize
    @http = HTTPClient.new
    @access_token ||= authorize
  end
  
  def config     
    file_path = File.expand_path('../../config.yml', __FILE__)
    @config ||= YAML.load_file(file_path)
  end
  
  def authorize(email = nil, pass = nil)
    email   ||= config['vk']['user']['email']
    pass    ||= config['vk']['user']['pass']
    client_id = config['vk']['client']
    
    response = @http.get 'https://oauth.vk.com/authorize', 
            { :client_id     => client_id, 
              :scope         => 'audio',
    			    :display       => 'wap', 
              :response_type => 'token', 
              :redirect_uri  => 'http://oauth.vk.com/blank.html',
    			    :v             => '5.14' }

    # Parse inputs on this form
    page  = Nokogiri::HTML::Document.parse(response.body)
    link  = page.css("form")[0]["action"] + '&'
    link += page.css("input[type='hidden']").map { |input| "#{input['name']}=#{input['value']}" }.join('&')
    link += "&email=#{email}&pass=#{pass}"

    response             = @http.post link
    response_redirect    = @http.get response.headers['Location']
    grant_access_request = @http.get response_redirect.headers['Location']

    # Get accees_token from last response
    url_with_access_token = grant_access_request.headers['Location']
    @access_token         = url_with_access_token[/#.+&/].tr_s('#','').split('&').first
  end
  
  def list_audios
    vk_api   = config['vk']['api']
    user_id  = config['vk']['user']['id']
    response = @http.get "#{vk_api}audio.get?owner_id=#{user_id.to_s}&#{@access_token}"
    audios   = JSON.parse(response.body)
    audios["response"]
  end
  
  def download(index = 1, printable = false)
    audio          = list_audios[index] 
    response       = @http.head audio['url']
    content_length = response.header['Content-Length'][0].to_f
    file_name      = audio['title'].strip
    file_path      = "tmp/#{ file_name }.mp3"
    
    unless downloaded?(file_path, content_length)
      file         = File.open(file_path, "w+")      
      sum_chunks   = 0
      puts "Download file '#{ file_name }.mp3' started..."
      @http.get_content(audio['url']) do |chunk|
        file.write(chunk)
        sum_chunks += chunk.size
        show_progress(sum_chunks, content_length) if printable
      end
    end
  end
  
  def downloaded?(file_path, content_length)
    #puts "File exists?: #{File.exist?(file_name)}"
    File.exist?(file_path) && File.open(file_path, "r").size == content_length
  end
  
  def show_progress(progress, total, options = { percentage: true })
    percents = (progress/total.to_f * 100).to_i
    out = "\r[" + '#'* (percents/2) + '-' * (50 - percents/2) 
    out += if options[:percentage]
      "]#{percents}%"
    else
      progress_time = Time.at(progress).strftime("%M:%S")
      total_time    = Time.at(total).strftime("%M:%S")
      "] #{ progress_time }/#{ total_time }"
    end
    print out
  end
  
  def play(index = 1)
    threads   = []
    audio     = list_audios[index] 
    duration  = audio['duration']
    file_name = audio['title'].strip
    
    audio_thread = Thread.new {
      %x( afplay "tmp/#{ file_name }.mp3" )
    }
    title_thread = Thread.new {
      puts "Playing file '#{ file_name }.mp3'...\n"
      0.upto(duration) do |d|     
        show_progress d, duration, percentage: false
        sleep 1
      end
    }
    
    threads << title_thread
    threads << audio_thread
    threads.each { |thread| thread.join } 
  end
  
  def download_and_play(index = 1)
    threads = []
    download_thread = Thread.new {
      download(index)
    }
    play_thread = Thread.new {
      sleep(10.0)
      play(index)
    }
    threads << download_thread
    threads << play_thread
    threads.each { |thread| thread.join }
    
    index += 1
    puts "\nNext file #{ index } --->>"
    download_and_play index
  end
  
  def show_as_table(audios, options = {})
    audios_on_page = options[:count].to_i
    page           = options[:page].to_i
    pages_count    = (audios.size/audios_on_page).to_i + 1
    range          = Range.new(page * audios_on_page - audios_on_page, page * audios_on_page)
    table          = Terminal::Table.new do |t|
      t.title = "Music(Page: #{options[:page]} of #{pages_count})"
      t.headings = ['#', 'Title', 'Duration']
      audios.each_with_index do |audio, index|
        if range.include?(index + 1)         
          t << [ index + 1, "#{ truncate(audio['title']) }", "#{ (audio['duration']/60.0).round(2) }" ] 
        end
      end
    end
    puts table
  end
  
  def search(query)
    vk_api   = config['vk']['api']
    user_id  = config['vk']['user']['id']
    response = @http.get "#{vk_api}audio.search?q=#{query}&auto_complete=1&sort=2&#{@access_token}"
    audios   = JSON.parse(response.body)
    audios["response"]
  end
  
  private 
  
    def truncate(str)
      str.strip!
      if str.length > 80
        "#{ str[0...80] }..." 
      else
        str
      end
    end
end