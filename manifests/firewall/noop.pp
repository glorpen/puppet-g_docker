class g_docker::firewall::noop {
  class { ::g_docker::firewall:
    docker_config => {
      'iptables' => false,
      'ip_masq'  => false
    }
  }
}
