class g_docker::firewall::puppet {
  class { 'g_docker::firewall':
    helper        => 'g_docker::firewall::puppet_helper',
    docker_config => {
      'iptables'   => false,
      'ip_masq'    => false,
      'ip_forward' => false
    }
  }

  $bridge_ifaces = $::facts['g_docker']['networks'].filter | $net_config | {
    $net_config['driver'] == 'bridge'
  }.map | $net_config | {
    if $net_config['options']['com.docker.network.bridge.name'] {
      $iface = $net_config['options']['com.docker.network.bridge.name']
    } else {
      $iface = "br-${net_config['id'][0,12]}"
    }
    $iface
  }

  
}
