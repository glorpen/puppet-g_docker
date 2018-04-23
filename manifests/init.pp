class g_docker(
  Enum['noop','native','script'] $firewall_mode = 'noop',
  String $data_path = '/mnt/docker',
  String $basesize,
  String $vg_name,
  String $thinpool_name = 'docker-thin',
  String $thinpool_size,
  String $thinpool_metadata_size,
  Hash $instances = {},
  Hash $registries = {},
  Optional[String] $ipv6_cidr = undef,
  Hash $networks = {},
  Array[String] $insecure_registries = []
){
  
  include ::stdlib
  
  $firewall_base = "::g_docker::firewall::${firewall_mode}"
  contain $firewall_base

  $puppetizer_conf_path = '/etc/docker/puppetizer.conf.d'
  $_vol_name = regsubst($thinpool_name, '-', '--', 'G')

  file { $data_path:
    ensure => directory,
    backup => false,
    force => true,
    purge => true,
    recurse => true,
    recurselimit => 2 # /mnt/docker/<container name>/<bind name>
  }
  
  file { $puppetizer_conf_path:
    ensure => directory,
    backup => false,
    force => true,
    purge => true,
    recurse => true,
    require => Class[::docker]
  }
  
  if $ipv6_cidr == undef {
    $_docker_ipv6_params = []
  } else {
    $_docker_ipv6_params = ['--ipv6', '--fixed-cidr-v6', $ipv6_cidr]
  }
  $_docker_insecure_reg_params = $insecure_registries.map | $n | {
    "--insecure-registry ${n}"
  }
  
  $_docker_params = concat(['--userland-proxy=false'], $_docker_ipv6_params, $_docker_insecure_reg_params)
  
  # /var/lib/docker -> mostly for volumes data
  g_server::volumes::thinpool { $thinpool_name:
    vg_name => $vg_name,
    size => $thinpool_size,
    metadata_size => $thinpool_metadata_size
  }->
  class { ::docker:
    log_driver => 'syslog',
    storage_driver => 'devicemapper',
    dm_basesize => $basesize,
    storage_vg => $vg_name,
    dm_thinpooldev => "/dev/mapper/${vg_name}-${_vol_name}",
    dm_blkdiscard => true,
    
    extra_parameters => $_docker_params,
    ip_forward => true,
    * => getvar("${firewall_base}::docker_config")
  }
  
  create_resources(::g_docker::run, $instances)
  create_resources(::docker::registry, $registries)
  create_resources(::g_docker::network, $networks)
  

}
