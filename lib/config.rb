require 'yaml'
require 'highline/import'

module Config
  
  def self.file_path
    File.expand_path('../../config.yml', __FILE__)
  end
  
  def self.configure
    @config   = YAML.load_file(file_path)
  rescue Errno::ENOENT, Psych::SyntaxError # file not found, syntax error
    puts "Config file not found or contains invalid syntax, so please enter required data."
    api       = 'https://api.vk.com/method/'
    client_id = ask("Enter your app id:  ", Integer) 
    user_id   = ask("Enter your user id:  ", Integer) 
    email     = ask("Enter your email:  ") { |q| q.validate = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i }
    pass      = ask("Enter your password:  ") { |q| q.echo = false }
    @config   = { "api" => api, "client" => client_id, "user" => { "id" => user_id, "email" => email, "pass" => pass } }
    store(@config)
  end
  
  def self.store(data, options = { clear: true })
    open_mode = options[:clear] ? 'w' : 'a'
    File.open(file_path, open_mode) do |file|
      file.write data.to_yaml
    end
    data
  end
  
end