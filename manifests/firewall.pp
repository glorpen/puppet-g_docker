class g_docker::firewall(
){
  # TODO: passing $bridge parameter or detecting?
  $default_network = $::facts['docker']['networks'].filter | $v | {
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
  
  $re_ifaces = $::facts['docker']['networks'].filter | $net_config | {
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

# TODO: skrypt tworzący rules w zadanym CHAINie a ten chain jest już tworzony przez puppet'a tak jak i przepływ do niego
# TODO: docker --iptables=false --userland-proxy=false
# może pozbyć się bridge i zrobić macvlan? https://github.com/docker/libnetwork/blob/master/docs/macvlan.md
# macvlan w dockerze + host na interfejsie virtualnym który potem jest forwardowny przez iptables itp
# albo jakaś kombinacja, nawet nie potrzeba consula by między hostami mogły się komunikować
#dla ipv6:
#ip6tables -t nat $flag POSTROUTING -s fd00:abcd:abcd::/48 ! -o docker0 -j MASQUERADE
#ip6tables -t nat $flag PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination [fd00:abcd:abcd::242:ac11:3]:80
# ... albo tymczasowo pominąć ipv6 - bo jak rules wyglądają w swarm? containery powinny się widzieć więć jakiś dns-server musi być

# kontenery mogą mieć cap-add net_admin i zarządzać swoimi iptables wewnątrz, chyba nie mogą wpłynąć na hosta

# zostaje bridge dockerowe, tylko dochodzi skrypt zarządający iptables
# 1. czy da się rules dockera wpakować do osobnych chain? prościej je łapać wtedy w puppecie
# 2. puppet ignoruje te chainy ale sam dodaje miejce przeskoku do nich
# 3. jeśli potrzeba, kontener sam zarządza swoimi iptables, ale pewnie host też mozę rules przed chainem dodać

}
