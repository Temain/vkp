require 'test_helper'

class VkontaktePlayerTest < Test::Unit::TestCase
  
  def setup
    @vkp = VkontaktePlayer.new
  end

  def teardown
  end

  def test_user_data_loading
    assert('10209453', @vkp.config['vk']['user']['id'].to_s)
    assert('temain@mail.ru', @vkp.config['vk']['user']['email'])
  end
  
  def test_getting_access_token 
    access_token = @vkp.authorize
    assert_not_nil(access_token, "Access token is nil")
  end
  
end


