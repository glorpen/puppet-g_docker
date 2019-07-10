class g_docker::swarm(
  String $cluster_iface,
  Optional[String] $manager_ip = undef,
  Optional[String] $token = undef,
  String $node_name = $::fqdn
){
  include ::g_docker

  $_swarm_init = $manager_ip?{
    undef   => true,
    default => false
  }
  $_swarm_join = $manager_ip?{
    undef   => false,
    default => true
  }
  ::docker::swarm { $node_name:
    init           => $_swarm_init,
    join           => $_swarm_join,
    manager_ip     => $manager_ip,
    advertise_addr => $cluster_iface,
    listen_addr    => $cluster_iface,
    token          => $token
  }

  g_firewall { '105 allow inbound docker swarm tcp':
    dport   => [2377, 7946],
    proto   => tcp,
    action  => accept,
    iniface => $cluster_iface
  }
  g_firewall { '105 allow inbound docker swarm udp':
    dport   => [4789, 7946],
    proto   => udp,
    action  => accept,
    iniface => $cluster_iface
  }
}
