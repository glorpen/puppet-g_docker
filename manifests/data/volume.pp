define g_docker::data::volume(
  String $data_name,
  String $size,
  String $volume_name = $title,
  Hash[String, Hash] $binds = {},
  Enum['present','absent'] $ensure = 'present',
  Optional[Integer] $raid = undef,
  Optional[Integer] $mirrors = undef,
  Optional[Integer] $stripes = undef,
  Optional[String] $fs = undef,
  Optional[String] $fs_options = undef,
  Optional[String] $mount_options = undef,
  Optional[Integer] $pass = undef
){
  include ::g_docker

  $lv_name = "${data_name}_${volume_name}"
  $mountpoint = "${::g_docker::data_path}/${data_name}/${volume_name}"

  $_volume_options = {
    ensure        => $ensure,
    vg_name       => $::g_docker::data_vg_name,
    size          => $size,
    mountpoint    => $mountpoint,
    fs            => $fs,
    fs_options    => $fs_options,
    mount_options => $mount_options
  }

  if $raid == undef {
    g_server::volumes::vol { $lv_name:
      * => $_volume_options
    }
    $_volume_resource = G_server::Volumes::Vol[$lv_name]
  } else {
    g_server::volumes::raid { $lv_name:
      level   => $raid,
      mirrors => $mirrors,
      stripes => $stripes,
      *       => $_volume_options
    }
    $_volume_resource = G_server::Volumes::Raid[$lv_name]
  }

  $binds.each | $bind_name, $bind_conf | {
    g_docker::data::bind { "${data_name}:${volume_name}:${bind_name}":
      ensure      => $ensure,
      data_name   => $data_name,
      volume_name => $volume_name,
      bind_name   => $bind_name,
      user        => $bind_conf['user'],
      group       => $bind_conf['group'],
      mode        => $bind_conf['mode'],
      require     => $_volume_resource
    }
  }

  if $ensure == 'present' {
    File["${::g_docker::data_path}/${data_name}"]
    ->$_volume_resource
  } else {
    $_volume_resource
    ->File["${::g_docker::data_path}/${data_name}"]
  }
}
