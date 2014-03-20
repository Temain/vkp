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
    
    puts "Authorize in vk..."
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
  rescue Exception => e
    puts e.message
  end
  
end