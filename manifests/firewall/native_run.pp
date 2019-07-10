define g_docker::firewall::native_run(
  Integer $host_port,
  String $protocol,
  Boolean $host_network,
  G_server::Side $port_side,
  Enum['present','absent'] $ensure = 'present'
){
  if $host_network {
    g_firewall { "200 docker publish ${name}":
      ensure => $ensure,
      dport  => $host_port,
      proto  => $protocol,
      action => 'accept'
    }
  } else {
    g_server::get_interfaces($port_side).each | $iface | {
      g_firewall::ipv6 { "200 docker publish ${name} on ${iface}":
        ensure  => $ensure,
        dport   => $host_port,
        proto   => $protocol,
        iniface => $iface,
        action  => 'accept'
      }
    }

    if ($port_side in ['external', 'both']) {
      g_server::get_interfaces('external').each | $iface | {
        g_firewall::ipv4 { "200 docker publish ${iface}":
          ensure  => $ensure,
          dport   => $host_port,
          proto   => $protocol,
          action  => 'accept',
          iniface => $iface,
          before  => G_firewall::Ipv4["199 docker world isolation on ${iface}"]
        }
      }
    }
  }
}
