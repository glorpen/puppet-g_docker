define g_docker::firewall::puppet_network(
  Enum['present', 'absent'] $ensure = 'present',
  Boolean $external_access = false
){
  $config = g_docker::find_network_config($name)
  $iface = g_docker::find_network_interface($name)

  if $iface {
    g_firewall::ipv4 { "150 docker bridge ${iface} allow estabilished connections":
      ensure   => $ensure,
      chain    => 'FORWARD',
      outiface => $iface,
      proto    => 'all',
      action   => 'accept',
      ctstate  => ['RELATED', 'ESTABLISHED']
    }

    g_firewall::ipv4 { "150 docker bridge ${iface} allow forwarding to itself":
      ensure   => $ensure,
      chain    => 'FORWARD',
      iniface  => $iface,
      outiface => $iface,
      proto    => 'all',
      action   => 'accept',
    }

    g_server::get_interfaces('external').each | $ex_iface | {
      g_firewall::ipv4 { "150 docker bridge ${iface} allow forwarding to ${ex_iface}":
        ensure   => $ensure,
        chain    => 'FORWARD',
        iniface  => $iface,
        outiface => $ex_iface,
        proto    => 'all',
        action   => 'accept',
      }

      $config['ipam']['config'].each | $ipam | {
        $subnet = $ipam['subnet']
        if $subnet =~ Stdlib::IP::Address::V4::CIDR {
          g_firewall::ipv4 { "150 docker bridge ${iface} nat to ${ex_iface}":
            ensure   => $ensure,
            table    => 'nat',
            chain    => 'POSTROUTING',
            source   => $subnet,
            outiface => $ex_iface,
            proto    => 'all',
            jump     => 'MASQUERADE',
          }
        }
      }
    }
  }
}
