require 'vkp/version.rb'
require 'yaml'
require 'uri'
require 'net/http'
require 'net/https'
require 'openssl'	
require 'nokogiri'
require 'httpclient'
require 'json'
require 'config'

class VkontaktePlayer
  
  def initialize
    @http = HTTPClient.new
    access_token
  end
  
  attr_writer :http
 
  def access_token
    if @expires_in == nil || Time.now >= @expires_in 
      authorize  
    end
    @access_token
  end
 
  def config     
    @config ||= Config::configure
  end
  
 # Вместе с ключом access_token также будет указано время его жизни expires_in,
 #  заданное в секундах. Если срок использования ключа истек, 
 #  то необходимо повторно провести все описанные выше шаги, 
 #  но в этом случае пользователю уже не придется дважды разрешать доступ. 
 #  Запрашивать access_token также необходимо при смене пользователем логина или пароля
 #  или удалением приложения в настройках доступа. 
  def authorize
    email   ||= config['user']['email']
    pass    ||= config['user']['pass']
    client_id = config['client']
    response  = @http.get 'https://oauth.vk.com/authorize', 
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
    
    @expires_in   = Time.now + url_with_access_token[/&expires_in=.+&/].tr_s('&','').sub!('expires_in=','').to_i
    user_id       = url_with_access_token[/&user_id=.+/].tr_s('&','').sub!('user_id=','').to_i
    
    # Save user id
    @config['user'].merge! "id" => user_id
    Config::save(@config)
    @access_token = url_with_access_token[/#.+&/].tr_s('#','').split('&').first
  end
  
  def list_audios
    vk_api   = config['api']
    user_id  = config['user']['id']
    response = @http.get "#{vk_api}audio.get?owner_id=#{user_id.to_s}&#{access_token}"
    body     = JSON.parse(response.body)
    @audios  = body["response"]
    @audios.delete_at(0) # don't need
    @audios
  end
  
  def download(index = 1, printable = false)
    audio          = @audios[index] 
    response       = @http.head audio['url']
    content_length = response.header['Content-Length'][0].to_f
    file_name      = audio['title'].strip
    file_path      = "tmp/#{ file_name }.mp3"
    
    unless downloaded?(file_path, content_length)
      file = File.open(file_path, "w+")      
      puts "Download file '#{ file_name }.mp3' started..."
      sum_chunks = 0
      @http.get_content(audio['url']) do |chunk|
        file.write(chunk)
        sum_chunks += chunk.size
        show_progress(sum_chunks, content_length) if printable
      end
    end
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
  
  def play(index)
    threads   = []
    audio     = @audios[index] 
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
  
  def show_as_table(options = {})
    audios_on_page = options[:count].to_i
    page           = options[:page].to_i
    pages_count    = (@audios.size/audios_on_page).to_i + 1
    range          = Range.new(page * audios_on_page - audios_on_page, page * audios_on_page)
    table = Terminal::Table.new do |t|
      t.title = "Music(Page: #{options[:page]} of #{pages_count})"
      t.headings = ['#', 'Title', 'Duration']
      @audios.each_with_index do |audio, index|
        if range.include?(index + 1)   
          duration = Time.at(audio['duration']).strftime("%M:%S")      
          t << [ index + 1, "#{ truncate(audio['title']) }", "#{ duration }" ] 
        end
      end
    end
    puts table
  end
  
  def search(query)
    vk_api   = config['api']
    user_id  = config['user']['id']
    response = @http.get "#{vk_api}audio.search?q=#{URI.encode(query)}&auto_complete=1&sort=2&#{access_token}"
    body     = JSON.parse(response.body)
    @audios  = body["response"]
    @audios.delete_at(0) # don't need
    @audios
  end
  
  def to_yaml_properties
    [:@access_token, :@expires_in, :@audios]
  end
  
  def serialize
    data = self.to_yaml
    file_path = File.expand_path('../../store.yml', __FILE__) #DRY!--fix this
    File.open(file_path, 'w') do |file|
      file.write data
    end
  end
  
  def self.deserialize   
    file_path = File.expand_path('../../store.yml', __FILE__)
    deserialized = YAML.load_file(file_path)
    deserialized.http = HTTPClient.new
    deserialized
  rescue Errno::ENOENT, Psych::SyntaxError # file not found, syntax error
    VkontaktePlayer.new
  end
  
  private 
  
    def downloaded?(file_path, content_length)    
      File.exist?(file_path) && File.open(file_path, "r").size == content_length
    end
  
    def truncate(str)
      str.strip!
      if str.length > 80
        "#{ str[0...80] }..." 
      else
        str
      end
    end
    
end