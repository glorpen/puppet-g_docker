class g_docker(
  Enum['noop','native','script'] $firewall_mode = 'noop',
  String $data_path = '/mnt/docker',
  String $basesize,
  String $vg_name,
  String $thinpool_name = 'docker-thin',
  String $thinpool_size,
  String $thinpool_metadata_size,
  Hash $instances = {},
  Hash $registries = {}
){
  
  include ::stdlib
  
  $firewall_base = "::g_docker::firewall::${firewall_mode}"
  contain $firewall_base

  $puppetizer_conf_path = '/etc/docker/puppetizer.conf.d'

  file { $data_path:
    ensure => directory,
    backup => false,
    force => true,
    purge => true,
    recurse => true
  }
  
  file { $puppetizer_conf_path:
    ensure => directory,
    backup => false,
    force => true,
    purge => true,
    recurse => true
  }
  
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
    dm_thinpooldev => "/dev/mapper/${vg_name}-docker--thin",
    # TODO: function to normalize dev name for LVM 
    dm_blkdiscard => true,
    
    extra_parameters => ['--userland-proxy=false'],
    ip_forward => true,
    * => getvar("${firewall_base}::docker_config")
  }
  
  create_resources(::g_docker::run, $instances)
  create_resources(::docker::registry, $registries)
  #TODO: fix with linematch resource and https://github.com/puppetlabs/puppetlabs-docker/issues/15
  

}
