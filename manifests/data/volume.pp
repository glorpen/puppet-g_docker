define g_docker::data::volume(
  String $data_name,
  String $size,
  String $volume_name = $title,
  Hash[String, Hash] $binds = {},
  Enum['present','absent'] $ensure = 'present'
){
  include ::g_docker

  $lv_name = "${data_name}_${volume_name}"
  $mountpoint = "${::g_docker::data_path}/${data_name}/${volume_name}"

  g_server::volumes::vol { $lv_name:
    ensure     => $ensure,
    vg_name    => $::g_docker::data_vg_name,
    size       => $size,
    mountpoint => $mountpoint,
  }

  $binds.each | $bind_name, $bind_conf | {
    ::g_docker::data::bind { "${data_name}:${volume_name}:${bind_name}":
      ensure      => $ensure,
      data_name   => $data_name,
      volume_name => $volume_name,
      bind_name   => $bind_name,
      user        => $bind_conf['user'],
      group       => $bind_conf['group'],
      mode        => $bind_conf['mode']
    }
  }

  if $ensure == 'present' {
    File["${::g_docker::data_path}/${data_name}"]
    ->G_server::Volumes::Vol[$lv_name]
  } else {
    G_server::Volumes::Vol[$lv_name]
    ->File["${::g_docker::data_path}/${data_name}"]
  }
}
