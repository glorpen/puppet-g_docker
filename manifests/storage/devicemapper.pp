class g_docker::storage::devicemapper(
  Enum['present', 'absent'] $ensure = 'present',
  String $basesize,
  String $vg_name,
  String $thinpool_name = 'docker-thin',
  String $thinpool_size,
  String $thinpool_metadata_size
){
  $_vol_name = regsubst($thinpool_name, '-', '--', 'G')
  $_vg_name = regsubst($vg_name, '-', '--', 'G')
  
  if $ensure == 'present' {
    class {::g_docker::storage:
      docker_config => {
        storage_driver => 'devicemapper',
        dm_basesize => $basesize,
        storage_vg => $vg_name,
        dm_thinpooldev => "/dev/mapper/${_vg_name}-${_vol_name}",
        dm_blkdiscard => true,
      }
    }
    
    G_server::Volumes::Thinpool[$thinpool_name] -> Class[::docker]
  } else {
    Class[::docker] -> G_server::Volumes::Thinpool[$thinpool_name] 
  }
  
  # /var/lib/docker -> mostly for volumes data
  g_server::volumes::thinpool { $thinpool_name:
    ensure => $ensure,
    vg_name => $vg_name,
    size => $thinpool_size,
    metadata_size => $thinpool_metadata_size
  }
}
