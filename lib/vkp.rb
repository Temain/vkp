require 'vkp/version.rb'
require 'yaml'
require 'net/http'
require 'net/https'
require 'openssl'	
require 'nokogiri'
require 'httpclient'
require 'json'

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
    email ||= config['vk']['user']['email']
    pass  ||= config['vk']['user']['pass']
    
    response = @http.get 'https://oauth.vk.com/authorize', 
            { :client_id     => 3537610, 
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
  # rescue Exception => e
 #    puts e.message
  end
  
  def list_audios(count = 16)
    @access_token ||= authorize
    vk_api   = config['vk']['api']
    user_id  = config['vk']['user']['id']
    response = @http.get "#{vk_api}audio.get?owner_id=#{user_id.to_s}&count=#{count}&#{@access_token}"
    audios   = JSON.parse(response.body)
    audios["response"]
  end
  
  def download(index = 1)
    audio    = list_audios[index] 
    response = @http.head audio['url']
    content_length = response.header['Content-Length'][0].to_f
    file     = File.open("tmp/#{audio['title']}.mp3","w+")
    
    sum_chunks = 0
    puts "Download file '#{audio['title']}.mp3' started..."
    @http.get_content(audio['url']) do |chunk|
      file.write(chunk)
      sum_chunks += chunk.size
      progress = (sum_chunks/content_length * 100).to_i
      print_string  = "\r["
      print_string += '#'* (progress/2) + '-' * (50 - progress/2)
      print_string += "]#{progress}%"
      print print_string
    end
    puts "\nFile '#{audio['title']}.mp3' has been downloaded."
  end
  
  def play(index = 1)
    audio = list_audios[index] 
    puts "Playing #{audio['title']}.mp3"
    %x( afplay "tmp/#{audio['title']}.mp3" )
  end
  
  def download_and_play(index = 1)
    threads = []
    http_thread = Thread.new {
      download(index)
    }
    audio_thread = Thread.new {
      sleep(5.0)
      play(index)
    }
    threads << http_thread
    threads << audio_thread
    threads.each { |thread| thread.join }
  end
  
end