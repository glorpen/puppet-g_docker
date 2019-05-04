class g_docker::storage::devicemapper(
  String $basesize,
  String $thinpool_size,
  String $thinpool_metadata_size,
  String $thinpool_name = 'docker-thin',
  Optional[String] $vg_name = undef,
  Enum['present', 'absent'] $ensure = 'present'
){
  $_vol_name = regsubst($thinpool_name, '-', '--', 'G')
  $_vg_name = regsubst($vg_name, '-', '--', 'G')

  if $ensure == 'present' {
    $_storage_vg = $vg_name?{
      undef   => $::g_docker::data_vg_name,
      default => $vg_name
    }
    class {'g_docker::storage':
      docker_config => {
        storage_driver => 'devicemapper',
        dm_basesize    => $basesize,
        storage_vg     => $_storage_vg,
        dm_thinpooldev => "/dev/mapper/${_vg_name}-${_vol_name}",
        dm_blkdiscard  => true,
      }
    }

    G_server::Volumes::Thinpool[$thinpool_name] -> Class[::docker]
  } else {
    Class[::docker] -> G_server::Volumes::Thinpool[$thinpool_name]
  }

  # /var/lib/docker -> mostly for volumes data
  g_server::volumes::thinpool { $thinpool_name:
    ensure        => $ensure,
    vg_name       => $vg_name,
    size          => $thinpool_size,
    metadata_size => $thinpool_metadata_size
  }
}
