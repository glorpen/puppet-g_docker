# @summary Creates docker networks.
#
# @param ensure
#   Create or remove network.
# @param driver
#   Driver to use for this network.
# @param subnets
#   List of subnets for network eg. ['10.0.0.0/24', ...]
# @param gateways
#   Gateway for subnet.
# @param ranges
#   Ranges to allocate IPs from.
# @param options
#   Additional driver options.
# @param internal
#   Restrict external access to the network.
#
define g_docker::network(
  Enum['present', 'absent'] $ensure = 'present',
  String $driver = 'bridge',
  Array[G_docker::IP::Address::CIDR] $subnets = [],
  Array[Stdlib::IP::Address::Nosubnet] $gateways = [],
  Array[G_docker::IP::Address::CIDR] $ranges = [],
  Hash[String, Stdlib::IP::Address::Nosubnet] $aux_addresses = {},
  Hash $options = {},
  Boolean $internal = true
){

  $_flags_internal = $internal ? {
    true => ['--internal'],
    default => []
  }

  docker_network { $name:
    ensure           => $ensure,
    driver           => $driver,
    subnet           => $subnets,
    gateway          => $gateways,
    ip_range         => $ranges,
    aux_address      => $aux_addresses.map | $k, $v | {
      "${k}=${v}"
    },
    options          => $options.map | $k, $v | {
      "${k}=${v}"
    },
    additional_flags => $_flags_internal,
    require          => Class['docker']
  }
}
