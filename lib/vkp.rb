require 'vkp/version.rb'
require 'yaml'
require 'net/http'
require 'net/https'
require 'openssl'	
require 'nokogiri'
require 'httpclient'
require 'json'
require 'timers'

# Add requires for other files you add to your project here, so
# you just need to require this one file in your bin file

class VkontaktePlayer
  
  def initialize
    @http = HTTPClient.new
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
  
  def list_audios(count = 16)
    @access_token ||= authorize
    vk_api   = config['vk']['api']
    user_id  = config['vk']['user']['id']
    response = @http.get "#{vk_api}audio.get?owner_id=#{user_id.to_s}&count=#{count}&#{@access_token}"
    audios   = JSON.parse(response.body)
    audios["response"]
  end
  
  def download(index = 1, printable = false)
    audio          = list_audios[index] 
    response       = @http.head audio['url']
    content_length = response.header['Content-Length'][0].to_f
    file_name      = "tmp/#{audio['title']}.mp3"
    
    unless downloaded?(file_name, content_length)
      file         = File.open(file_name, "w+")      
      sum_chunks   = 0
      puts "Download file '#{audio['title']}.mp3' started..."
      @http.get_content(audio['url']) do |chunk|
        file.write(chunk)
        sum_chunks += chunk.size
        show_progress(sum_chunks, content_length) if printable
      end
      # puts "\nFile '#{audio['title']}.mp3' has been downloaded."
    end
  end
  
  def downloaded?(file_name, content_length)
    puts "File exists?: #{File.exist?(file_name)}"
    # puts "File size: #{file.size}, Content-Length : #{content_length}"
    File.exist?(file_name) && File.open(file_name, "r").size == content_length
  end
  
  def show_progress(progress, total)
    percents = (progress/total.to_f * 100).to_i
    print "\r[" + '#'* (percents/2) + '-' * (50 - percents/2) + "]#{percents}%"
  end
  
  def play(index = 1)
    threads  = []
    audio    = list_audios[index] 
    duration = audio['duration'] 
    
    audio_thread = Thread.new {
      %x( afplay "tmp/#{audio['title']}.mp3" )
    }
    title_thread = Thread.new {
      puts "Playing file '#{audio['title']}.mp3'...\n"
      duration.times do |d|
        show_progress d, duration
        sleep 1
      end
    }
    
    threads << title_thread
    threads << audio_thread
    threads.each { |thread| thread.join } 
  end
  
  def download_and_play(index = 1)
    threads = []
    http_thread = Thread.new {
      download(index)
    }
    play_thread = Thread.new {
      sleep(5.0)
      play(index)
    }
    threads << http_thread
    threads << play_thread
    threads.each { |thread| thread.join }
  end
  
end