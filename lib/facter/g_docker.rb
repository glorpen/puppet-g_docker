require 'json'

begin
  require 'facter/util/common'
  require 'facter/util/http_unix'
rescue LoadError => e
  # puppet apply does not add module lib directories to the $LOAD_PATH (See
  # #4248). It should (in the future) but for the time being we need to be
  # defensive which is what this rescue block is doing.
  ['common.rb', 'http_unix.rb'].each do |fname|
    rb_file = File.join(File.dirname(File.dirname(__FILE__)), 'util', fname)
    load rb_file if File.exist?(rb_file) or raise e
  end
end

Facter.add(:g_docker) do
  confine :kernel => :linux
  setcode do
    networks = []
    version = nil
    installed = false

    # puppet code should ensure that socket exists
    client = Facter::Util::Docker::HTTPUnix.new('unix:///var/run/docker.sock')

    begin
      req = Net::HTTP::Get.new('/networks')
      data_networks = JSON.parse(client.request(req).body)

      networks = data_networks.map do |v|
        Facter::Util::Docker.underscore_hash(v)
      end.sort do |a, b|
        a['id'] <=> b['id']
      end

      req = Net::HTTP::Get.new('/version')
      data_version = JSON.parse(client.request(req).body)

      version = data_version['Version']

      installed = true
    rescue Exception => e
      Facter.debug("Failed to load api data as fact: #{e.class}: #{e}")
    end

    {
      networks: networks,
      version: version,
      installed: installed,
    }
  end
end
