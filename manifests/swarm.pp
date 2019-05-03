class g_docker::swarm(
  String $cluster_iface,
  Optional[String] $manager_ip = undef,
  Optional[String] $token = undef
){
  include ::g_docker

  $vg_name = $::g_docker::data_vg_name
  $cluster_addr = $::facts['networking']['interfaces'][$cluster_iface]['ip']

  ::docker::swarm { $::fqdn:
    init           => $manager_ip?{
      undef => true,
      default => false
    },
    join           => $manager_ip?{
      undef => false,
      default => true
    },
    manager_ip => $manager_ip,
    advertise_addr => $cluster_addr,
    listen_addr    => $cluster_addr,
    token => $token
  }
  
  g_firewall { '105 allow inbound docker swarm tcp':
    dport    => [2377, 7946],
    proto    => tcp,
    action   => accept,
    iniface => $cluster_iface
  }
  g_firewall { '105 allow inbound docker swarm udp':
    dport    => [4789, 7946],
    proto    => udp,
    action   => accept,
    iniface => $cluster_iface
  }
}
