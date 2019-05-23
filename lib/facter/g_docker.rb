require 'json'

require_relative '../g_docker_util/http_unix'
require_relative '../g_docker_util/common'

Facter.add(:g_docker) do
  confine kernel: 'Linux'
  setcode do
    networks = []
    version = nil
    installed = false

    # puppet code should ensure that socket exists
    client = NetX::HTTPUnix.new('unix:///var/run/docker.sock')

    begin
      req = Net::HTTP::Get.new('/networks')
      data_networks = JSON.parse(client.request(req).body)

      networks = data_networks.map { |v| GDockerUtil.underscore_hash(v) }.sort_by { |a| a['id'] }

      req = Net::HTTP::Get.new('/version')
      data_version = JSON.parse(client.request(req).body)

      version = data_version['Version']

      installed = true
    rescue StandardError => e
      Facter.debug("Failed to load api data as fact: #{e.class}: #{e}")
    end

    {
      'networks'  => networks,
      'version'   => version,
      'installed' => installed,
    }
  end
end
