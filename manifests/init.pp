class g_docker(
  Boolean $manage_firewall = true,
  String $data_path = '/mnt/docker',
  String $basesize,
  String $vg_name,
  String $thinpool_name = 'docker-thin',
  String $thinpool_size,
  String $thinpool_metadata_size,
){
  if $manage_firewall {
    class {::g_docker::firewall: }
  }

  file { $data_path:
    ensure => directory,
    backup => false,
    force => true
  }
  
  # /var/lib/docker -> mostly for volumes data
  g_server::volumes::thinpool { $thinpool_name:
    vg_name => $vg_name,
    size => $thinpool_size,
    metadata_size => $thinpool_metadata_size
  }->
  class {'docker':
    log_driver => 'syslog',
    storage_driver => 'devicemapper',
    dm_basesize => $basesize,
    storage_vg => $vg_name,
    dm_thinpooldev => "/dev/mapper/${vg_name}-docker--thin",
    # TODO: function to normalize dev name for LVM 
    dm_blkdiscard => true
  }
}
