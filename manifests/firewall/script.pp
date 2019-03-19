class g_docker::firewall::script {

  include ::stdlib
  ensure_packages(['python-docker-py'], {'ensure'=>'present'})
  
  ['IPv4', 'IPv6'].each | $ip_type | {
    firewallchain { "DOCKER-POSTROUTING:nat:${ip_type}":
      ensure => present,
      purge => false
    }
    firewallchain { "DOCKER:nat:${ip_type}":
      ensure => present,
      purge => false
    }
    firewallchain { "DOCKER-FORWARD:filter:${ip_type}":
      ensure => present,
      purge => false
    }
    firewallchain { "DOCKER-ISOLATION:filter:${ip_type}":
      ensure => present,
      purge => false
    }
    firewallchain { "DOCKER:filter:${ip_type}":
      ensure => present,
      purge => false
    }
  }
  
  g_firewall { '210 docker local prerouting':
    #'-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER'
    table => 'nat',
    chain => 'PREROUTING',
    jump => 'DOCKER',
    dst_type => 'LOCAL',
    proto    => 'all'
  }
  g_firewall { '211 docker local prerouting':
    #-A OUTPUT -m addrtype --dst-type LOCAL -j DOCKER
    table => 'nat',
    chain => 'OUTPUT',
    jump => 'DOCKER',
    dst_type => 'LOCAL',
    proto    => 'all'
  }
  g_firewall { '212 docker script postrouting':
    #-A POSTROUTING -o docker0 -m addrtype --src-type LOCAL -j MASQUERADE
    table => 'nat',
    chain => 'POSTROUTING',
    jump => 'DOCKER-POSTROUTING',
    proto    => 'all'
  }
  g_firewall { '213 docker isolation':
    #-A FORWARD -j DOCKER-ISOLATION
    table => 'filter',
    chain => 'FORWARD',
    jump => 'DOCKER-ISOLATION',
    proto    => 'all'
  }
  g_firewall { '214 docker forward':
    table => 'filter',
    chain => 'FORWARD',
    jump => 'DOCKER-FORWARD',
    proto    => 'all'
  }
  
  class { ::g_docker::firewall:
    docker_config => {
      "iptables" => false,
      "ip_masq" => false
    }
  }

#  file { '/usr/local/bin/docker-firewall':
#    ensure => 'file',
#    source => 'puppet:///modules/g_docker/dockertables.py',
#    mode => 'a=rx,u+w'
#  }
  
#  docker_network { 'local':
#    ensure   => present,
#    driver   => 'bridge',
#    subnet   => ['172.17.0.0/16', 'fd00:abcd::/48'],
#    gateway  => ['172.17.0.1', 'fd00:abcd::1'],
#    options => [
#      "com.docker.network.bridge.default_bridge=true",
#      "com.docker.network.bridge.enable_icc=true",
#      "com.docker.network.bridge.enable_ip_masquerade=true",
#      "com.docker.network.bridge.host_binding_ipv4=0.0.0.0",
#      "com.docker.network.bridge.name=docker0",
#      "com.docker.network.driver.mtu=1500"
#    ]
#  }
}
