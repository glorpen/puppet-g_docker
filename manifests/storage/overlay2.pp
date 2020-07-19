# @summary Configures Docker overlay storage
#
# @param size
#   Volume size
# @param vg_name
#   Volume group to use, leave empty if no LVM is available
#
class g_docker::storage::overlay2(
  String $size = '5G',
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
