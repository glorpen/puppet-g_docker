# define: g_docker::data::bind
#
# This definition creates container volume mount point.
#
# Parameters:
#   [*ensure*]                     - Enables or disables the specified server (present|absent)
#   [*data_name*]                  - Name of data directory, used in LVM volume naming
#   [*volume_name*]                - Name of data sub-directory, used in LVM volume naming
#   [*bind_name*]                  - Name of bind directory (just a folder), for sharing space on single LVM volume
#   [*user*]                       - Host user name/id to use as directory owner
#   [*group*]                      - Host group name/id to use as directory owner
#   [*mode*]                       - Permissions for directory
#   [*source*]                     - Set to manage directory content (eg. "puppet:///...")
#   [*puppetized*]                 - Informs bind that container is based on puppetized image
#
define g_docker::data::bind(
  String $data_name,
  String $volume_name,
  String $bind_name = $title,
  Optional[Variant[String, Integer]] $user = undef,
  Optional[Variant[String, Integer]] $group = undef,
  Optional[String] $mode = undef,
  Optional[String] $source = undef,
  Boolean $puppetized = false,
  Enum['present','absent'] $ensure = 'present'
){
  $lv_name = "${data_name}_${volume_name}"
  $bind_path = "${::g_docker::data_path}/${data_name}/${volume_name}/${bind_name}"

  if $ensure == 'present' {
    $_bind_path_ensure = $ensure?{
      'present' => directory,
      default   => $ensure
    }
    $_bind_path_recurse = $source?{
      undef   => false,
      default => true
    }
    file { $bind_path:
      ensure  => $_bind_path_ensure,
      backup  => false,
      force   => true,
      recurse => $_bind_path_recurse,
      owner   => $user,
      group   => $group,
      mode    => $mode,
      source  => $source
    }

    G_server::Volumes::Vol[$lv_name]
    ->File[$bind_path]

    if $puppetized {
      File[$bind_path]
      ~>Exec["puppetizer runtime apply for docker-${data_name}"]
    } else {
      File[$bind_path]
      ->Docker::Run[$data_name]
    }
  }

  # when ensure=absent, volume would be already removed
  # so no Files need to be deleted
}
