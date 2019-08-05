class g_docker::firewall::puppet (
  Enum['present', 'absent'] $ensure = 'present',
  Boolean $manage_ip_forward = true
){
  class { 'g_docker::firewall':
    helper        => 'g_docker::firewall::puppet_helper',
    docker_config => {
      'iptables'   => false,
      'ip_masq'    => false,
      'ip_forward' => false
    }
  }

  if ($manage_ip_forward) {
    file {'/etc/sysctl.d/docker.conf':
      ensure  => $ensure,
      content => "net.ipv4.ip_forward = 0\n"
    }
  }
}
