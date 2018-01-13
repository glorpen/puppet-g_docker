require 'json'

begin
  require 'facter/util/common'
  require 'facter/util/http_unix'
rescue LoadError => e
  # puppet apply does not add module lib directories to the $LOAD_PATH (See
  # #4248). It should (in the future) but for the time being we need to be
  # defensive which is what this rescue block is doing.
  ["common.rb", "http_unix.rb"].each do | fname |
    rb_file = File.join(File.dirname(File.dirname(__FILE__)), 'util', fname)
    load rb_file if File.exists?(rb_file) or raise e
  end
end

Facter.add(:g_docker) do
  confine :kernel => :linux
  setcode do
    
    networks = []
    
    # puppet code should ensure that socket exists
    client = Facter::Util::Docker::HTTPUnix.new('unix:///var/run/docker.sock')
    
    begin
      req = Net::HTTP::Get.new("/networks")
      networks = JSON.parse(client.request(req).body).map do | v |
        Facter::Util::Docker.underscore_hash(v)
      end.sort do | a, b |
        a["id"] <=> b["id"]
      end
    rescue Exception => e
      Facter.warn("Failed to load network data as fact: #{e.class}: #{e}")
    end
    
    {
      networks: networks
    }
  end
end
