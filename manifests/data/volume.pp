define g_docker::data::volume(
  String $data_name,
  String $volume_name = $title,
  String $vg_name,
  String $size,
  Hash $binds = {}
){
  $lv_name = "${data_name}_${volume_name}"
  g_server::volumes::vol { $lv_name:
    vg_name => $vg_name,
    size => $size,
    mountpoint => "${::g_docker::data_path}/${data_name}/${volume_name}",
    require => File["${::g_docker::data_path}/${data_name}"],
  }
  
  create_resources(::g_docker::data::bind, $binds, {
    data_name => $data_name,
    volume_name => $volume_name
  })
}
