define g_docker::network(
  String $driver = 'bridge',
  Array[String] $subnets = [],
  Array[String] $gateways = [],
  Array[String] $ranges = [],
  Hash $aux_addresses = {},
  Hash $options = {}
){
  docker_network { $name:
    ensure => present,
    driver => $driver,
    subnet => $subnets,
    gateway => $gateways,
    ip_range => $ranges,
    aux_address => $aux_addresses.map | $k, $v | {
      "${k}=${v}"
    },
    options => $options.map | $k, $v | {
      "${k}=${v}"
    }
  }
}
