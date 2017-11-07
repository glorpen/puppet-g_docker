define g_docker::data::volume(
  String $data_name,
  String $volume_name = $title,
  String $size,
  Hash $binds = {}
){
  include ::g_docker
  
  $lv_name = "${data_name}_${volume_name}"
  g_server::volumes::vol { $lv_name:
    vg_name => $::g_docker::vg_name,
    size => $size,
    mountpoint => "${::g_docker::data_path}/${data_name}/${volume_name}",
    require => File["${::g_docker::data_path}/${data_name}"],
  }
  
  $binds.each | $bind_name, $bind_config | {
    ::g_docker::data::bind { "${data_name}:${volume_name}:${bind_name}":
      data_name => $data_name,
      volume_name => $volume_name,
      bind_name => $bind_name
    }
  }
}
