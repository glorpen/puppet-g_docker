# @summary This definition creates container volume mount point.
#
# @param ensure
#   Enables or disables the specified server (present|absent)
# @param data_name
#   Name of data directory, used in LVM volume naming
# @param volume_name
#   Name of data sub-directory, used in LVM volume naming
# @param bind_name
#   Name of bind directory (just a folder), for sharing space on single LVM volume
# @param user
#   Host user name/id to use as directory owner
# @param group
#   Host group name/id to use as directory owner
# @param mode
#   Permissions for directory
#
define g_docker::data::bind(
  String $data_name,
  String $volume_name,
  String $bind_name = $title,
  Optional[Variant[String, Integer]] $user = undef,
  Optional[Variant[String, Integer]] $group = undef,
  Optional[String] $mode = undef,
  Enum['present','absent'] $ensure = 'present'
){
  $lv_name = "${data_name}_${volume_name}"
  $bind_path = "${::g_docker::data_path}/${data_name}/${volume_name}/${bind_name}"

  if $ensure == 'present' {
    $_bind_path_ensure = $ensure?{
      'present' => directory,
      default   => $ensure
    }
    file { $bind_path:
      ensure  => $_bind_path_ensure,
      backup  => false,
      force   => true,
      recurse => false,
      owner   => $user,
      group   => $group,
      mode    => $mode,
      #source  => $source
    }

    G_server::Volumes::Vol[$lv_name]
    ->File[$bind_path]
    ->Docker::Run[$data_name]
  }

  # when ensure=absent, volume would be already removed
  # so no Files need to be deleted
}
