# @summary Configures Docker Swarm
#
# @param cluster_iface
#   Interface that will be used to communicate with other nodes.
# @param manager_ip
#   Address of existing manager to connect to when initializing.
# @param token
#   Token to use when joining swarm.
# @param firewall_mode
#   Open swarm ports to whole cluster_iface ('interface') or for each other swarm node separately ('node').
#
class g_docker::swarm(
  String $cluster_iface,
  Optional[String] $manager_ip = undef,
  Optional[String] $token = undef,
  String $node_name = $::fqdn,
  Array[Tuple[Stdlib::IP::Address::V4::CIDR, Integer]] $address_pools = [],
  Enum['interface', 'node'] $firewall_mode = 'interface',
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

  $_firewall_rules = {
    'udp' => {
        'dport'  => [2377, 7946],
        'proto'  => tcp,
        'action' => accept,
    },
    'tcp' => {
      'dport'  => [4789, 7946],
      'proto'  => udp,
      'action' => accept,
    }
  }

  case $firewall_mode {
    'interface': {
      $_firewall_rules.each | $proto, $config | {
        g_firewall { "105 allow inbound docker swarm ${proto}":
          iniface => $cluster_iface,
          *       => $config
        }
      }
    }
    'node': {
      $_firewall_rules.each | $proto, $rule_config | {
        $rule_name = "105 allow inbound docker swarm ${proto} from ${node_name}"
        $config = merge($rule_config, {
          source => $_listen_addr,
          tag    => 'g_docker::swarm::node'
        })
        if $_listen_addr =~ Stdlib::IP::Address::V6 {
          @@g_firewall::ipv6 { $rule_name: * => $config}
        } else {
          @@g_firewall::ipv4 { $rule_name: * => $config}
        }
      }

      puppetdb_query("resources[type, title, parameters]{exported=true and tag='g_docker::swarm::node' and certname !='${trusted['certname']}'}").each | $info | {
        ensure_resource($info['type'], $info['title'], merge($info['parameters'], {
          iniface => $cluster_iface
        }))
      }
    }
    default: {}
  }
}
