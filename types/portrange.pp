type G_docker::PortRange = Variant[
  Pattern[
    /^[0-9]+$/,
    /^[0-9]+\-[0-9]+$/
  ],
  Stdlib::Port
]
