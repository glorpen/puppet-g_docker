class g_docker::swarm(
  String $cluster_iface,
  Optional[String] $manager_ip = undef,
  Optional[String] $token = undef,
  String $node_name = $::fqdn,
  Array[Tuple[Stdlib::IP::Address::V4::CIDR, Integer]] $address_pools = [],
){
  include ::g_docker

  $_swarm_opts = {
    'init' => $manager_ip?{
      undef   => true,
      default => false
    },
    'join' => $manager_ip?{
      undef   => false,
      default => true
    },
  }

  if (empty($address_pools)) {
    $_swarm_pool_opts = {}
  } else {
    $address_pools.each |$item, $index| {
      if ($item[1] != $address_pools[0][1]) {
        fail("Swarm address pools should have same size, ${item[1]} found on ${index} pool")
      }
    }
    $_swarm_pool_opts = {
      'default_addr_pool' => $address_pools.map |$i| { $i[0] },
      'default_addr_pool_mask_length' => $address_pools[0][1]
    }
  }

  # choose single IP if multiple addresses are found on given interface
  $_network_info = $::facts['networking']['interfaces'][$cluster_iface]
  if ($_network_info['bindings'].length > 1 or $_network_info['bindings6'].length > 1) {
    if $_network_info['bindings'] {
      $_listen_addr = $::facts['networking']['interfaces'][$cluster_iface]['ip']
    } else {
      $_listen_addr = $::facts['networking']['interfaces'][$cluster_iface]['ip6']
    }
  } else {
    $_listen_addr = $cluster_iface
  }

  ::docker::swarm { $node_name:
    manager_ip     => $manager_ip,
    advertise_addr => $_listen_addr,
    listen_addr    => $_listen_addr,
    token          => $token,
    *              => $_swarm_opts + $_swarm_pool_opts
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
