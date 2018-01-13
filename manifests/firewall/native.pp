class g_docker::firewall::native {
  
  $docker_config = {
    "iptables" => true,
    "ip_masq" => true
  }
  
  # TODO: passing $bridge parameter or detecting?
  $default_network = $::facts['g_docker']['networks'].filter | $v | {
      $v["options"]["com.docker.network.bridge.default_bridge"] == "true"
  }[0]
  
  if $default_network == undef {
    warning('Docker default network was not found')
    $re_subnets = []
  } else {
    $re_subnets = $default_network["ipam"]["config"].map | $v | {
      $parts = $v["subnet"].split('/')
      $mask = Integer($parts[1])
      
      $parts[0].split('\\.').map | $i, $v | {
        # a. b. c. d
        # 08 16 24 32 
        if ($i + 1) * 8 > $mask {
          '[0-9]+'
        } else {
          $v
        }
      }.join('\\.')
    }
  }
  
  $re_ifaces = $::facts['g_docker']['networks'].filter | $net_config | {
    # TODO: overlay, custom(?)
    $net_config['driver'] == 'bridge'
  }.map | $net_config | {
    if $net_config["options"]["com.docker.network.bridge.name"] {
      $iface = $net_config["options"]["com.docker.network.bridge.name"]
    } else {
      $iface = "br-${net_config['id'][0,12]}"
    }
    if $iface {
      ["-i ${iface} ", "-o ${iface} "]
    }
  }.flatten
  
  g_firewall::protect { 'docker ipv4 rules1':
    regex => $re_ifaces + [' -j DOCKER'],
    chain => 'FORWARD:filter:IPv4'
  }
  g_firewall::protect { 'docker ipv4 rules4':
    regex => $re_ifaces,
    chain => 'POSTROUTING:nat:IPv4'
  }
  g_firewall::protect { 'docker ipv4 rules2':
    regex => ['-j DOCKER'],
    chain => 'PREROUTING:nat:IPv4'
  }
  g_firewall::protect { 'docker ipv4 rules3':
    regex => ['-j DOCKER'],
    chain => 'OUTPUT:nat:IPv4'
  }
  g_firewall::protect { "docker port publish":
    regex => $re_subnets.map | $rs | {
      "-s ${rs}/32 -d ${rs}/32 .* -j MASQUERADE\$"
    },
    chain => 'POSTROUTING:nat:IPv4'
  }
  
  firewallchain { "DOCKER:filter:IPv4":
    ensure => present,
    purge => false,
    require => Class['docker']
  }
  firewallchain { "DOCKER-ISOLATION:filter:IPv4":
    ensure => present,
    purge => false,
    require => Class['docker']
  }
  firewallchain { "DOCKER:nat:IPv4":
    ensure => present,
    purge => false,
    require => Class['docker']
  }




}
