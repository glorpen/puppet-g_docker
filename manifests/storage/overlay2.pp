class g_docker::storage::overlay2(
  String $size,
  Enum['present', 'absent'] $ensure = 'present',
  Optional[String] $vg_name = undef,
  String $lv_name = 'docker-data',
  Optional[Integer] $raid_level = undef,
  Optional[Integer] $raid_stripes = undef,
  Optional[Integer] $raid_mirrors = undef
){
  if $ensure == 'present' {
    class {'g_docker::storage':
      docker_config => {
        storage_driver => 'overlay2'
      },
      helper        => 'g_docker::storage::overlay2_helper'
    }
  }
}
