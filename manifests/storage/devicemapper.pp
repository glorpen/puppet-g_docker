# @summary Configures Docker to use devicemapper as storage backend.
#
# @param basesize
#   Default size for running containers, eg. 2G
# @param thinpool_size
#   Thin pool size.
# @param thinpool_metadata_size
#   Size of thinpool metadata.
# @param thinpool_name
#   Thinpool name to use.
# @param vg_name
#  Volume group to use.
#
class g_docker::storage::devicemapper(
  String $basesize,
  String $vg_name,
  String $thinpool_size,
  String $thinpool_metadata_size,
  String $thinpool_name = 'docker-thin',
  Enum['present', 'absent'] $ensure = 'present'
){
  $_vol_name = regsubst($thinpool_name, '-', '--', 'G')
  $_vg_name = regsubst($vg_name, '-', '--', 'G')

  if $ensure == 'present' {
    class {'g_docker::storage':
      docker_config => {
        storage_driver => 'devicemapper',
        dm_basesize    => $basesize,
        storage_vg     => $_vg_name,
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
    vg_name       => $_vg_name,
    size          => $thinpool_size,
    metadata_size => $thinpool_metadata_size
  }
}
