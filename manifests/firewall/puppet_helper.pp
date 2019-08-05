class g_docker::firewall::puppet_helper {

  $ensure = $g_docker::firewall::puppet::ensure

  $default_network = $::facts['g_docker']['networks'].filter | $v | {
      # lint:ignore:quoted_booleans
      $v['options']['com.docker.network.bridge.default_bridge'] == 'true'
      # lint:endignore
  }[0]['name']

  g_docker::firewall::puppet_network { $default_network:
    ensure => $ensure,
    external_access => true
  }
}
