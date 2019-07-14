define g_docker::network(
  String $ensure = 'present',
  String $driver = 'bridge',
  Array[String] $subnets = [],
  Array[String] $gateways = [],
  Array[String] $ranges = [],
  Hash $aux_addresses = {},
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
