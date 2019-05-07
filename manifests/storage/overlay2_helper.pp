class g_docker::storage::overlay2_helper{

  include ::g_docker::storage::overlay2

  $ensure = $::g_docker::storage::overlay2::ensure
  $vg_name = pick($::g_docker::storage::overlay2::vg_name, $::g_docker::data_vg_name)
  $lv_name = $::g_docker::storage::overlay2::lv_name
  $size = $::g_docker::storage::overlay2::size

  if $ensure == 'present' {
    G_server::Volumes::Vol[$lv_name] -> Class['docker']
  } else {
    Class['docker'] -> G_server::Volumes::Vol[$lv_name]
  }

  g_server::volumes::vol { $lv_name:
    ensure     => $ensure,
    vg_name    => $vg_name,
    size       => $size,
    fs         => 'xfs',
    fs_options => '-n ftype=1',
    mountpoint => $::g_docker::docker_data_path
  }
}
